import uuid

import pytest

from app import safety
from app.mock_data import segments, textile_tear
from app.models import AnalyzeResponse, ClassifyResult, FollowUpQuestion, Safety


def resp(category="textile", risk="allowed", plan=None, segs=None) -> AnalyzeResponse:
    plan = plan or textile_tear()
    return AnalyzeResponse(
        case_id=str(uuid.uuid4()), category=category, risk_level=risk, safety=Safety(),
        segments=segs if segs is not None else segments("textile_tear"),
        diagnosis=plan.diagnosis, decision=plan.decision, shopping_list=plan.shopping_list, guide=plan.guide,
    )


def test_allowed_keeps_guide():
    r = safety.enforce(resp(), has_answers=True)
    assert not r.safety.blocked and r.safety.reason is None
    assert r.guide.steps and r.shopping_list


@pytest.mark.parametrize("category,risk", [
    ("textile", "warn_only"), ("shoe", "professional"), ("unsupported", "allowed"), ("unsupported", "warn_only"),
])
def test_blocked_forces_empty(category, risk):
    r = safety.enforce(resp(category, risk), has_answers=False)
    assert r.safety.blocked and r.safety.reason
    assert r.shopping_list == [] and r.guide.steps == []


def test_needs_more_info_empties_lists_but_not_blocked():
    plan = textile_tear()
    plan.diagnosis.needs_more_info = True
    plan.diagnosis.follow_up_questions = [FollowUpQuestion(id="q1", type="photo", prompt="x", purpose="label")]
    r = safety.enforce(resp(plan=plan), has_answers=False)
    assert not r.safety.blocked and r.guide.steps == [] and r.shopping_list == []


def test_followup_questions_max_three():
    plan = textile_tear()
    plan.diagnosis.needs_more_info = True
    plan.diagnosis.follow_up_questions = [
        FollowUpQuestion(id=f"q{i}", type="choice", prompt="?") for i in range(5)
    ]
    r = safety.enforce(resp(plan=plan), has_answers=False)
    assert len(r.diagnosis.follow_up_questions) == 3


def test_low_confidence_without_answers_asks():
    plan = textile_tear()
    plan.diagnosis.confidence = 0.4
    r = safety.enforce(resp(plan=plan), has_answers=False)
    assert r.diagnosis.needs_more_info and len(r.diagnosis.follow_up_questions) == 1
    assert r.guide.steps == []


def test_answers_force_needs_more_info_false():
    plan = textile_tear()
    plan.diagnosis.needs_more_info = True
    plan.diagnosis.follow_up_questions = [FollowUpQuestion(id="q1", type="photo", prompt="x")]
    r = safety.enforce(resp(plan=plan), has_answers=True)
    assert r.diagnosis.needs_more_info is False and r.diagnosis.follow_up_questions == []
    assert r.decision.recommendation == "repair_self"  # confidence still fine


def test_answers_low_confidence_repair_pro():
    plan = textile_tear()
    plan.diagnosis.confidence = 0.5
    plan.diagnosis.needs_more_info = True
    r = safety.enforce(resp(plan=plan), has_answers=True)
    assert r.decision.recommendation == "repair_pro"
    assert r.diagnosis.needs_more_info is False and r.guide.steps == []


def test_confidence_clamped():
    for raw, want in [(1.7, 1.0), (-0.3, 0.0), (float("nan"), 0.0)]:
        plan = textile_tear()
        plan.diagnosis.confidence = raw
        r = safety.enforce(resp(plan=plan), has_answers=True)
        assert r.diagnosis.confidence == want or r.diagnosis.confidence == min(want, r.diagnosis.confidence)
    plan = textile_tear()
    plan.diagnosis.confidence = 1.7
    assert safety.enforce(resp(plan=plan), has_answers=True).diagnosis.confidence == 1.0


def test_invalid_segment_refs_dropped():
    plan = textile_tear()
    plan.diagnosis.evidence_segment_ids = ["seg_2", "seg_99"]
    plan.guide.steps[0].segment_ids = ["seg_99", "seg_2"]
    plan.guide.steps[3].overlay.segment_id = "seg_77"
    r = safety.enforce(resp(plan=plan), has_answers=True)
    assert r.diagnosis.evidence_segment_ids == ["seg_2"]
    assert r.guide.steps[0].segment_ids == ["seg_2"]
    assert r.guide.steps[3].overlay is None


def test_uses_items_must_exist_and_unused_items_dropped():
    plan = textile_tear()
    for s in plan.guide.steps:
        s.uses_items = [i for i in s.uses_items if i != "item_5"] + ["item_404"]
    r = safety.enforce(resp(plan=plan), has_answers=True)
    ids = {i.id for i in r.shopping_list}
    assert "item_5" not in ids
    for s in r.guide.steps:
        assert "item_404" not in s.uses_items and set(s.uses_items) <= ids
    used = {u for s in r.guide.steps for u in s.uses_items}
    assert ids == used


def test_estimate_note_forced():
    plan = textile_tear()
    plan.decision.estimate_note = "Garantiert!"
    assert safety.enforce(resp(plan=plan), has_answers=True).decision.estimate_note == "Schätzung, keine Garantie"


def test_safety_critical_requires_confirmation():
    plan = textile_tear()
    plan.guide.steps[1].requires_confirmation = False
    plan.guide.steps[1].safety_critical = True
    r = safety.enforce(resp(plan=plan), has_answers=True)
    assert all(s.requires_confirmation for s in r.guide.steps if s.safety_critical)


def test_steps_renumbered():
    plan = textile_tear()
    plan.guide.steps[0].n = 9
    r = safety.enforce(resp(plan=plan), has_answers=True)
    assert [s.n for s in r.guide.steps] == list(range(1, len(r.guide.steps) + 1))


# ---- keyword pre-check -----------------------------------------------------------

@pytest.mark.parametrize("note,risk", [
    ("Netzteil Kabel kaputt", "warn_only"),
    ("Akku ist aufgebläht", "warn_only"),
    ("Lithium-Ionen Zelle", "warn_only"),
    ("läuft mit 230V", "warn_only"),
    ("beheizbare Jacke", "warn_only"),
    ("Kondensator im Blitzgerät", "warn_only"),
    ("Gasherd Dichtung", "warn_only"),
    ("Fahrradhelm Riss", "professional"),
    ("Kindersitz Gurt", "professional"),
    ("Bremse quietscht", "professional"),
    ("Sohle löst sich vorne", "allowed"),
    ("", "allowed"),
])
def test_precheck_keywords(note, risk):
    assert safety.precheck_note(note).risk_level == risk


def test_precheck_only_stricter():
    cls = ClassifyResult(category="textile", risk_level="professional", reason="r")
    assert safety.apply_precheck(cls, safety.precheck_note("Akku")).risk_level == "professional"
    cls = ClassifyResult(category="textile", risk_level="allowed", reason="r")
    out = safety.apply_precheck(cls, safety.precheck_note("Akku"))
    assert out.risk_level == "warn_only" and "Akku" in out.reason
    assert safety.apply_precheck(cls, safety.precheck_note("Riss")) == cls


def test_enforce_applies_precheck():
    r = safety.enforce(resp(), has_answers=False, precheck=safety.precheck_note("Netzteil"))
    assert r.safety.blocked and r.risk_level == "warn_only" and r.guide.steps == []


def test_step_help_escalation():
    assert safety.step_help_escalation("Es raucht, Rauch!", "allowed")
    assert safety.step_help_escalation("Das Eisen ist heiß", "allowed")
    assert not safety.step_help_escalation("Der Faden reißt", "allowed")
    assert safety.step_help_escalation("Faden reißt", "warn_only")
