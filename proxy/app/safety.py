"""Pure safety logic (PRD sections 7 and 8). No I/O, no model calls.

Everything here can only make the outcome stricter, never looser.
"""

import math
import re
from dataclasses import dataclass

from .models import (
    ESTIMATE_NOTE,
    AnalyzeResponse,
    ClassifyResult,
    FollowUpQuestion,
    Guide,
    RiskLevel,
)

CONFIDENCE_THRESHOLD = 0.6
MAX_QUESTIONS = 3

RISK_ORDER: dict[str, int] = {"allowed": 0, "warn_only": 1, "professional": 2}

_REASON_WARN = (
    "Dieser Gegenstand kann gefährlich sein (zum Beispiel Akku, Netzanschluss oder Gas). "
    "Dafür gibt es hier keine Reparaturanleitung. Bitte wende dich an den Hersteller oder einen Fachbetrieb."
)
_REASON_PRO = (
    "Dieser Gegenstand ist sicherheitsrelevant. Bitte lass ihn von einem Fachbetrieb prüfen oder ersetzen."
)
_REASON_UNSUPPORTED = "Dieses Objekt wird nicht unterstützt. Die App hilft nur bei Textilien und Schuhen."

# (pattern, risk, short German label)
_KEYWORDS: list[tuple[re.Pattern[str], RiskLevel, str]] = [
    (re.compile(p, re.IGNORECASE), risk, label)
    for p, risk, label in [
        (r"akku", "warn_only", "Akku"),
        (r"lithium|li-?ion|lipo\b", "warn_only", "Lithium"),
        (r"netzteil|ladeger[aä]t|netzbetrieb|steckdose|netzkabel|netzstecker", "warn_only", "Netzanschluss"),
        (r"230\s?v|240\s?v|110\s?v|netzspannung", "warn_only", "Netzspannung"),
        (r"kondensator|blitzger[aä]t", "warn_only", "Kondensator"),
        (r"beheizbar|heizjacke|heizweste|heizsohle|heizkissen|beheizt", "warn_only", "Heizelement"),
        (r"\bgas\b|gasger[aä]t|gasherd|gaskartusche|gasflasche", "warn_only", "Gas"),
        (r"led-?schuh|leuchtsohle|blinkschuh", "warn_only", "Elektronik im Schuh"),
        (r"\bhelm|helm\b", "professional", "Helm"),
        (r"kindersitz|kinderautositz|babyschale", "professional", "Kindersitz"),
        (r"bremse|bremsbelag|bremsscheibe", "professional", "Bremse"),
        (r"airbag|sicherheitsgurt|klettergurt|kletterseil|fallschirm", "professional", "Sicherheitsausrüstung"),
    ]
]


@dataclass(frozen=True)
class PreCheck:
    risk_level: RiskLevel
    reason: str | None
    matches: tuple[str, ...]


def stricter(a: RiskLevel, b: RiskLevel) -> RiskLevel:
    return a if RISK_ORDER[a] >= RISK_ORDER[b] else b


# "Kein Akku drin" blocked a battery-free USB lamp live (2026-10-29). Only an explicitly negated battery
# ("kein/keine/ohne … Akku/Lithium") is ignored; Prompt A still checks the photo for batteries, and every
# other hazard keyword stays conservative even when negated.
_NEGATED_BATTERY = re.compile(
    r"\b(?:kein(?:e|en|em|er)?|ohne)\s+(?:\w+\s+){0,2}?(?:akku[\w-]*|lithium[\w-]*|li-?ion[\w-]*|lipo)\b", re.IGNORECASE)


def precheck_note(note: str | None) -> PreCheck:
    """Keyword pre-check on the user's free text."""
    risk: RiskLevel = "allowed"
    matches: list[str] = []
    text = _NEGATED_BATTERY.sub(" ", note or "")
    for pattern, level, label in _KEYWORDS:
        if pattern.search(text):
            matches.append(label)
            risk = stricter(risk, level)
    if risk == "allowed":
        return PreCheck("allowed", None, ())
    reason = _REASON_PRO if risk == "professional" else _REASON_WARN
    return PreCheck(risk, f"{reason} (Hinweis aus deiner Beschreibung: {', '.join(matches)})", tuple(matches))


def apply_precheck(cls: ClassifyResult, pre: PreCheck) -> ClassifyResult:
    if RISK_ORDER[pre.risk_level] <= RISK_ORDER[cls.risk_level]:
        return cls
    return cls.model_copy(update={"risk_level": pre.risk_level, "reason": pre.reason or cls.reason})


def is_blocked(category: str, risk_level: str) -> bool:
    return risk_level != "allowed" or category == "unsupported"


def blocked_reason(category: str, risk_level: str, given: str | None) -> str:
    if given and given.strip():
        return given
    if risk_level == "professional":
        return _REASON_PRO
    if risk_level == "warn_only":
        return _REASON_WARN
    return _REASON_UNSUPPORTED


def _clamp01(value: float) -> float:
    if math.isnan(value):
        return 0.0
    return max(0.0, min(1.0, value))


def enforce(resp: AnalyzeResponse, *, has_answers: bool, precheck: PreCheck | None = None) -> AnalyzeResponse:
    """Apply all contract/safety rules to a response; returns a corrected copy."""
    r = resp.model_copy(deep=True)

    # --- risk / blocking ---
    if precheck and RISK_ORDER[precheck.risk_level] > RISK_ORDER[r.risk_level]:
        r.risk_level = precheck.risk_level
        r.safety.reason = precheck.reason
    blocked = is_blocked(r.category, r.risk_level)
    r.safety.blocked = blocked
    r.safety.reason = blocked_reason(r.category, r.risk_level, r.safety.reason) if blocked else None

    # --- diagnosis ---
    d, dec = r.diagnosis, r.decision
    d.confidence = _clamp01(d.confidence)
    d.follow_up_questions = d.follow_up_questions[:MAX_QUESTIONS]
    low = d.confidence < CONFIDENCE_THRESHOLD
    forced_pro = False
    if has_answers:
        # at most one follow-up round
        unresolved = low or d.needs_more_info
        d.needs_more_info = False
        d.follow_up_questions = []
        if unresolved and not blocked:
            dec.recommendation = "repair_pro"
            forced_pro = True
    elif not blocked and (low or d.needs_more_info):
        d.needs_more_info = True
        if not d.follow_up_questions:
            d.follow_up_questions = [
                FollowUpQuestion(
                    id="q1",
                    type="photo",
                    prompt="Mach bitte eine scharfe Nahaufnahme der Schadstelle aus einem anderen Winkel.",
                    purpose="closeup",
                )
            ]
    dec.estimate_note = ESTIMATE_NOTE
    dec.time_minutes = sorted(max(0, t) for t in dec.time_minutes)
    dec.cost_eur = sorted(max(0.0, c) for c in dec.cost_eur)

    # --- empty lists when no guide may exist ---
    if blocked or d.needs_more_info or forced_pro or dec.recommendation != "repair_self":
        r.shopping_list = []
        r.guide = Guide(steps=[])

    # --- references ---
    seg_ids = {s.id for s in r.segments}
    d.evidence_segment_ids = [i for i in d.evidence_segment_ids if i in seg_ids]
    item_ids = {i.id for i in r.shopping_list}
    used: set[str] = set()
    for step in r.guide.steps:
        step.segment_ids = [i for i in step.segment_ids if i in seg_ids]
        step.uses_items = [i for i in step.uses_items if i in item_ids]
        used.update(step.uses_items)
        if step.overlay:
            overlay = step.overlay
            targets = [overlay.segment_id]
            if overlay.type == "solder":
                targets = [overlay.from_segment_id, overlay.to_segment_id]
                end = next((s for s in r.segments if s.id == overlay.from_segment_id), None)
                pad = next((s for s in r.segments if s.id == overlay.to_segment_id), None)
                if (r.category != "low_voltage_electronics" or end is None or pad is None
                        or end.kind != "damage" or end.prompt != "copper wire strands"
                        or pad.kind != "part" or pad.source != "grounding" or pad.polarity not in {"+", "-"}):
                    step.overlay = None
                # Heat and fumes require acknowledgement even if the model omitted it.
                step.safety_critical = True
            if any(i not in seg_ids for i in targets):
                step.overlay = None
            if step.overlay:
                step.segment_ids.extend(i for i in targets if i not in step.segment_ids)
        if step.safety_critical:
            step.requires_confirmation = True
    r.shopping_list = [i for i in r.shopping_list if i.id in used]
    for n, step in enumerate(r.guide.steps, start=1):
        step.n = n
    return r


# ---- /step-help -------------------------------------------------------------

_ESCALATE = re.compile(r"rauch|hei(ß|ss)|akku|brenn|brand|funken|qualm|schmor|verbrenn|verätz", re.IGNORECASE)


def step_help_escalation(issue_text: str, risk_level: str) -> bool:
    return risk_level != "allowed" or bool(_ESCALATE.search(issue_text or ""))
