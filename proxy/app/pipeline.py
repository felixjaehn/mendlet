"""Analysis pipeline (PRD section 6): classify -> segment -> diagnose+plan, with safety enforcement."""

import asyncio
import logging
import uuid
from collections import Counter
from collections.abc import Awaitable, Callable

from . import i18n, safety
from .clients import ModelClient
from .errors import AppError, BudgetExceeded, ModelOutputError
from .models import (
    AnalyzeRequest,
    AnalyzeResponse,
    ClassifyResult,
    Decision,
    DiagnosePlan,
    Diagnosis,
    Safety,
    Segment,
    Stage,
)
from .sam import SEGMENT_PROMPTS

log = logging.getLogger("proxy.pipeline")

STAGES: tuple[Stage, ...] = ("classify", "segment", "diagnose", "plan")
STAGE_LABELS: dict[str, str] = i18n.STAGE_LABELS["de"]  # German default; use stage_label() for a locale


def stage_label(stage: str, locale: str | None = None) -> str:
    return i18n.pick(i18n.STAGE_LABELS, locale)[stage]


Progress = Callable[[Stage], Awaitable[None]]
GroundingProgress = Callable[[], Awaitable[None]]
SegmentsReady = Callable[[list[Segment]], Awaitable[None]]
AgentStepEvent = Callable[[dict], Awaitable[None]]
CLASSIFY_FALLBACK_REASON = {
    "de": "Das Objekt konnte nicht sicher eingeordnet werden. Im Zweifel geben wir keine Anleitung.",
    "en": "The object could not be classified reliably. When in doubt, we do not give a guide.",
}


async def _noop(_: Stage) -> None:
    return None


async def _noop_grounding() -> None:
    return None


async def _noop_segments(_: list[Segment]) -> None:
    return None


async def _noop_step(_: dict) -> None:
    return None


def blocked_response(cls: ClassifyResult, pre: safety.PreCheck, locale: str | None = None) -> AnalyzeResponse:
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
    return safety.enforce(resp, has_answers=False, precheck=pre, locale=locale)


UNSURE_TEXT_DAMAGE = 0.7
PRECISE_RATIO = 0.15  # grounded damage box under 15 % of a SAM damage box around it replaces that box


def _xyxy(seg: Segment) -> tuple[float, float, float, float] | None:
    if not seg.box:
        return None
    x, y, w, h = seg.box
    return (x, y, x + w, y + h)


def _area(seg: Segment) -> float:
    return seg.box[2] * seg.box[3] if seg.box else 0.0


def _overlaps(a: Segment, b: Segment) -> bool:
    """IoU > 0.3 or one box mostly inside the other: both segments mark the same damage.
    (0.1 merged a leather shoe's open heel seam into the sole box at IoU 0.103 live.)"""
    ba, bb = _xyxy(a), _xyxy(b)
    if ba is None or bb is None:
        return False
    ix = max(0.0, min(ba[2], bb[2]) - max(ba[0], bb[0]))
    iy = max(0.0, min(ba[3], bb[3]) - max(ba[1], bb[1]))
    inter = ix * iy
    area_a, area_b = (ba[2] - ba[0]) * (ba[3] - ba[1]), (bb[2] - bb[0]) * (bb[3] - bb[1])
    union = area_a + area_b - inter
    smaller = min(area_a, area_b)
    return (union > 0 and inter / union > 0.3) or (smaller > 0 and inter / smaller > 0.6)


def _free_id(segments: list[Segment]) -> str:
    index = len(segments) + 1
    while f"seg_{index}" in {s.id for s in segments}:
        index += 1
    return f"seg_{index}"


async def _classic_segments(
    req: AnalyzeRequest, client: ModelClient, cls: ClassifyResult, grounding: GroundingProgress
) -> list[Segment]:
    if cls.category == "low_voltage_electronics":
        # Bare ends are damage, but never replace the independently grounded destination pads.
        await grounding()
        results = await asyncio.gather(
            client.segment(req, cls.category, SEGMENT_PROMPTS[cls.category]),
            client.ground(req, cls.category),
            return_exceptions=True,
        )
        segments = []
        for result in results:
            if isinstance(result, (BudgetExceeded, asyncio.CancelledError)):
                raise result
            if isinstance(result, AppError):
                log.warning("electronics segmentation unavailable: %s", result.code)
            elif isinstance(result, BaseException):
                raise result
            else:
                for segment in result:
                    segments.append(segment.model_copy(update={"id": f"seg_{len(segments) + 1}"}))
        return segments
    # Live probe 2026-10-28 (docs/benchmark.md): SAM text prompts find parts but rarely damage
    # ("tear" = 0 matches on an obvious tear), so Spark grounding runs in parallel instead of after.
    # It always runs to completion so its result is cached; cancelling would re-spend credits on replay.
    ground_task = asyncio.create_task(client.ground(req, cls.category))
    try:
        segments = await client.segment(req, cls.category, SEGMENT_PROMPTS.get(cls.category, []))
        if any(s.kind == "damage" for s in segments):
            # Benchmark 2026-10-29 (leather shoe): SAM flagged the sole while the damage was an open heel seam.
            # Spark's grounding is already paid for; keep its mask when no SAM damage covers the same spot.
            done = await asyncio.gather(ground_task, return_exceptions=True)
            grounded = done[0] if isinstance(done[0], list) else []
            if isinstance(done[0], BudgetExceeded):
                raise done[0]
            if grounded:
                # Benchmark 2026-10-29: SAM's uncertain text hits (< 0.7) away from where Spark sees the damage were
                # buttonholes, intact seams and a sound sole; dropping them removed 8 false positives, no real damage.
                segments = [
                    s
                    for s in segments
                    if s.kind != "damage" or s.score >= UNSURE_TEXT_DAMAGE or any(_overlaps(s, g) for g in grounded)
                ]
            for segment in grounded:
                # Real photo 2026-10-29 (leather sole): SAM's "detached sole" box covered the whole sole while Spark's
                # box sat exactly on the worn-through hole. A far smaller grounded box inside it is the precise one.
                broad = [
                    s
                    for s in segments
                    if s.kind == "damage" and _overlaps(segment, s) and _area(segment) < PRECISE_RATIO * _area(s)
                ]
                segments = [s for s in segments if s not in broad]
                if not any(_overlaps(segment, s) for s in segments if s.kind == "damage"):
                    segments.append(segment.model_copy(update={"id": _free_id(segments)}))
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


async def analyze(
    req: AnalyzeRequest,
    client: ModelClient,
    progress: Progress = _noop,
    grounding: GroundingProgress = _noop_grounding,
    segments_ready: SegmentsReady = _noop_segments,
    agent_step: AgentStepEvent = _noop_step,
) -> AnalyzeResponse:
    """Run the pipeline on an already prepared (downscaled) request."""
    pre = safety.precheck_note("\n".join([req.note, *(a.text for a in req.answers)]), req.locale)

    await progress("classify")
    try:
        cls = await client.classify(req)
    except ModelOutputError:
        log.warning("classify output invalid after retry; falling back to warn_only")
        cls = ClassifyResult(
            category="unsupported",
            risk_level="warn_only",
            reason=i18n.pick(CLASSIFY_FALLBACK_REASON, req.locale),
        )
    cls = safety.apply_precheck(cls, pre)
    if safety.is_blocked(cls.category, cls.risk_level):
        return blocked_response(cls, pre, req.locale)  # safety is decided here, never inside the agent

    await progress("segment")
    plan: DiagnosePlan | None = None
    segments: list[Segment] | None = None
    use_agent = req.agent if req.agent is not None else getattr(client, "agent_enabled", False)
    if use_agent and cls.category != "low_voltage_electronics":
        try:
            segments, plan = await client.agent_run(req, cls, agent_step)
        except BudgetExceeded:
            raise
        except AppError as exc:
            log.warning("agent failed (%s); falling back to the classic pipeline", exc.code)
            segments, plan = None, None
    if segments is None:
        segments = await _classic_segments(req, client, cls, grounding)
    segments = i18n.relabel(segments, req.locale)
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
    resp = safety.enforce(resp, has_answers=req.is_followup_round, precheck=pre, locale=req.locale)
    resp.instances = dict(Counter(s.prompt for s in resp.segments if s.kind == "damage"))
    return resp
