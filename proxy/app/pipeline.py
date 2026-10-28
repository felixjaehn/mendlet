"""Analysis pipeline (PRD section 6): classify -> segment -> diagnose+plan, with safety enforcement."""

import asyncio
import logging
import uuid
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
    Safety,
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


async def _noop(_: Stage) -> None:
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


async def analyze(req: AnalyzeRequest, client: ModelClient, progress: Progress = _noop) -> AnalyzeResponse:
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
        return blocked_response(cls, pre)

    await progress("segment")
    try:
        segments = await client.segment(req, cls.category, SEGMENT_PROMPTS.get(cls.category, []))
    except BudgetExceeded:
        raise
    except AppError as exc:
        # PRD §6: continue with text guidance when segmentation is unavailable.
        log.warning("segmentation unavailable: %s", exc.code)
        segments = []

    await progress("diagnose")
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
    return safety.enforce(resp, has_answers=req.is_followup_round, precheck=pre)
