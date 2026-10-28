"""Analysis pipeline (PRD section 6): classify -> segment -> diagnose+plan, with safety enforcement."""

import asyncio
import logging
import uuid
from collections import Counter
from collections.abc import Awaitable, Callable

from . import safety
from .clients import ModelClient
from .errors import AppError, BudgetExceeded, ModelOutputError
from .models import (
    AnalyzeRequest,
    AnalyzeResponse,
    ClassifyResult,
    Decision,
    Diagnosis,
    DiagnosePlan,
    Safety,
    Segment,
    Stage,
)
from .sam import SEGMENT_PROMPTS

log = logging.getLogger("proxy.pipeline")

STAGES: tuple[Stage, ...] = ("classify", "segment", "diagnose", "plan")
STAGE_LABELS: dict[str, str] = {
    "classify": "Objekt und Risiko prüfen",
    "segment": "Schadstelle markieren",
    "diagnose": "Schaden diagnostizieren",
    "plan": "Einkaufsliste und Anleitung erstellen",
}

Progress = Callable[[Stage], Awaitable[None]]
GroundingProgress = Callable[[], Awaitable[None]]
SegmentsReady = Callable[[list[Segment]], Awaitable[None]]
AgentStepEvent = Callable[[dict], Awaitable[None]]


async def _noop(_: Stage) -> None:
    return None


async def _noop_grounding() -> None:
    return None


async def _noop_segments(_: list[Segment]) -> None:
    return None


async def _noop_step(_: dict) -> None:
    return None


def blocked_response(cls: ClassifyResult, pre: safety.PreCheck) -> AnalyzeResponse:
    """Response without segments/guide. diagnosis/decision are filled placeholders so the contract stays complete."""
    reason = cls.reason
    resp = AnalyzeResponse(
        case_id=str(uuid.uuid4()),
        category=cls.category,
        risk_level=cls.risk_level,
        safety=Safety(blocked=True, reason=reason),
        segments=[],
        diagnosis=Diagnosis(
            summary=reason, likely_causes=[], confidence=0.0, evidence_segment_ids=[], needs_more_info=False
        ),
        decision=Decision(
            recommendation="repair_pro", reasoning=reason, effort="high", time_minutes=[0, 0], cost_eur=[0, 0]
        ),
        shopping_list=[],
        guide={"steps": []},  # type: ignore[arg-type]
    )
    return safety.enforce(resp, has_answers=False, precheck=pre)


async def _classic_segments(req: AnalyzeRequest, client: ModelClient, cls: ClassifyResult,
                            grounding: GroundingProgress) -> list[Segment]:
    # Live probe 2026-10-28 (docs/benchmark.md): SAM text prompts find parts but rarely damage
    # ("tear" = 0 matches on an obvious tear), so Spark grounding runs in parallel instead of after.
    # It always runs to completion so its result is cached; cancelling would re-spend credits on replay.
    ground_task = asyncio.create_task(client.ground(req, cls.category))
    try:
        segments = await client.segment(req, cls.category, SEGMENT_PROMPTS.get(cls.category, []))
        if any(s.kind == "damage" for s in segments):
            await asyncio.gather(ground_task, return_exceptions=True)
        else:
            await grounding()
            try:
                grounded = await ground_task
                for segment in grounded:
                    index = len(segments) + 1
                    while f"seg_{index}" in {s.id for s in segments}:
                        index += 1
                    segments.append(segment.model_copy(update={"id": f"seg_{index}"}))
            except BudgetExceeded:
                raise
            except AppError as exc:
                log.warning("grounding unavailable: %s", exc.code)
    except BudgetExceeded:
        await asyncio.gather(ground_task, return_exceptions=True)
        raise
    except AppError as exc:
        await asyncio.gather(ground_task, return_exceptions=True)
        # PRD §6: continue with text guidance when segmentation is unavailable.
        log.warning("segmentation unavailable: %s", exc.code)
        segments = []
    return segments


async def analyze(req: AnalyzeRequest, client: ModelClient, progress: Progress = _noop,
                  grounding: GroundingProgress = _noop_grounding, segments_ready: SegmentsReady = _noop_segments,
                  agent_step: AgentStepEvent = _noop_step) -> AnalyzeResponse:
    """Run the pipeline on an already prepared (downscaled) request."""
    pre = safety.precheck_note("\n".join([req.note, *(a.text for a in req.answers)]))

    await progress("classify")
    try:
        cls = await client.classify(req)
    except ModelOutputError:
        log.warning("classify output invalid after retry; falling back to warn_only")
        cls = ClassifyResult(
            category="unsupported", risk_level="warn_only",
            reason="Das Objekt konnte nicht sicher eingeordnet werden. Im Zweifel geben wir keine Anleitung.",
        )
    cls = safety.apply_precheck(cls, pre)
    if safety.is_blocked(cls.category, cls.risk_level):
        return blocked_response(cls, pre)  # safety is decided here, never inside the agent

    await progress("segment")
    plan: DiagnosePlan | None = None
    segments: list[Segment] | None = None
    if getattr(client, "agent_enabled", False):
        try:
            segments, plan = await client.agent_run(req, cls, agent_step)
        except BudgetExceeded:
            raise
        except AppError as exc:
            log.warning("agent failed (%s); falling back to the classic pipeline", exc.code)
            segments, plan = None, None
    if segments is None:
        segments = await _classic_segments(req, client, cls, grounding)
    await segments_ready(segments)

    await progress("diagnose")
    if plan is None:
        plan = await client.diagnose(req, cls, segments)

    await progress("plan")
    if client.plan_delay:
        await asyncio.sleep(client.plan_delay)

    resp = AnalyzeResponse(
        case_id=str(uuid.uuid4()),
        category=cls.category,
        risk_level=cls.risk_level,
        safety=Safety(blocked=False, reason=None),
        segments=segments,
        diagnosis=plan.diagnosis,
        decision=plan.decision,
        shopping_list=plan.shopping_list,
        guide=plan.guide,
    )
    resp = safety.enforce(resp, has_answers=req.is_followup_round, precheck=pre)
    resp.instances = dict(Counter(s.prompt for s in resp.segments if s.kind == "damage"))
    return resp
