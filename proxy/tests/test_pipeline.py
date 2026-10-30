import pytest

from app.mock_client import MockClient
from app.pipeline import analyze
from tests.conftest import make_req

C = MockClient(0.0)


async def run(image_b64, **kw):
    return await analyze(make_req(image_b64, **kw), C)


async def test_needs_label_first_call(image_b64):
    r = await run(image_b64, mock_scenario="textile_tear_needs_label")
    assert r.category == "textile" and r.risk_level == "allowed" and not r.safety.blocked
    assert r.diagnosis.needs_more_info and 0.5 <= r.diagnosis.confidence < 0.6
    q = r.diagnosis.follow_up_questions
    assert len(q) == 1 and q[0].type == "photo" and q[0].purpose == "label"
    assert r.segments and r.shopping_list == [] and r.guide.steps == []


async def test_default_is_textile_needs_label(image_b64):
    r = await run(image_b64, user_note="Riss in der Hose")
    assert r.diagnosis.needs_more_info


async def test_label_answer_changes_result(image_b64):
    first = await run(image_b64)
    second = await run(
        image_b64,
        answers=[{"question_id": "q1", "text": "98 % Baumwolle, 2 % Elasthan"}],
        extra_images=[{"purpose": "label", "image_base64": image_b64}],
    )
    assert first.diagnosis.needs_more_info and not second.diagnosis.needs_more_info
    assert second.diagnosis.label_info.materials == ["98 % Baumwolle", "2 % Elasthan"]
    assert second.decision.recommendation == "repair_self" and second.decision.effort == "low"
    assert second.decision.time_minutes == [20, 40] and second.decision.cost_eur == [3, 8]
    assert 6 <= len(second.guide.steps) <= 7
    assert any(s.safety_critical and s.requires_confirmation for s in second.guide.steps)
    assert any(
        s.overlay and s.overlay.stitch_type == "ladder_stitch" and s.overlay.segment_id == "seg_2"
        for s in second.guide.steps
    )
    assert "Elasthan" in " ".join(s.text for s in second.guide.steps)
    names = " ".join(i.name for i in second.shopping_list)
    for part in ["Nähnadel", "Polyestergarn", "Stecknadeln", "Schere", "Fingerhut", "Nahttrenner"]:
        assert part in names
    tear = next(s for s in second.segments if s.id == "seg_2")
    assert tear.mask.format == "polygon" and len(tear.mask.points) > 10
    assert tear.box[2] / max(tear.box[3], 1e-6) > 2  # elongated


async def test_label_changes_to_pure_cotton(image_b64):
    r = await run(image_b64, answers=[{"question_id": "q1", "text": "100 % Baumwolle"}])
    assert r.diagnosis.label_info.materials == ["100 % Baumwolle"]
    assert "Elasthan" not in " ".join(s.text for s in r.guide.steps)


async def test_hole_darning(image_b64):
    r = await run(image_b64, mock_scenario="textile_hole")
    assert r.guide.steps and any(s.overlay and s.overlay.stitch_type == "darning" for s in r.guide.steps)
    hole = next(s for s in r.segments if s.id == "seg_2")
    w, h = hole.box[2], hole.box[3]
    assert 0.7 < w / h < 1.4  # roughly round


@pytest.mark.parametrize("scenario,category", [("textile_open_seam", "textile"), ("textile_button", "textile")])
async def test_other_textile(image_b64, scenario, category):
    r = await run(image_b64, mock_scenario=scenario)
    assert r.category == category and r.guide.steps and not r.diagnosis.needs_more_info


async def test_shoe(image_b64):
    r = await run(image_b64, user_note="Sohle löst sich vorne")
    assert r.category == "shoe" and r.decision.recommendation == "repair_self" and r.decision.effort == "medium"
    text = " ".join(s.text for s in r.guide.steps)
    assert "24 Stunden" in text and "Gummibänder" in " ".join(i.household_alternative or "" for i in r.shopping_list)
    assert any(s.safety_critical for s in r.guide.steps)


@pytest.mark.parametrize(
    "kw,risk,category",
    [
        ({"mock_scenario": "battery_jacket"}, "warn_only", "textile"),
        ({"mock_scenario": "helmet"}, "professional", "unsupported"),
        ({"mock_scenario": "unsupported"}, "allowed", "unsupported"),
        ({"user_note": "Meine beheizbare Jacke mit Akku geht nicht mehr"}, "warn_only", "textile"),
    ],
)
async def test_blocked_scenarios(image_b64, kw, risk, category):
    r = await run(image_b64, **kw)
    assert r.category == category and r.safety.blocked and r.safety.reason
    assert r.risk_level == risk
    assert r.segments == [] and r.shopping_list == [] and r.guide.steps == []


# ---- safety cases ----------------------------------------------------


@pytest.mark.parametrize(
    "note",
    [
        "Netzteil von meinem Laptop, das Kabel wackelt",
        "Akku vom Staubsauger lädt nicht",
        "Fahrradhelm hat einen Riss",
        "Beheizbare Jacke mit Akku, Heizung geht nicht",
    ],
)
async def test_safety_cases_blocked(image_b64, note):
    r = await run(image_b64, user_note=note)
    assert r.risk_level != "allowed" or r.category == "unsupported"
    assert r.safety.blocked and r.guide.steps == [] and r.shopping_list == []


class NaiveClient(MockClient):
    """A model that wrongly says everything is fine: pre-check must still block."""

    async def classify(self, req):
        from app.mock_data import CLASSIFY

        return CLASSIFY["textile"]


@pytest.mark.parametrize("note", ["Netzteil Kabel", "Akku defekt", "Helm Riss", "beheizbare Jacke"])
async def test_precheck_blocks_even_if_model_says_allowed(image_b64, note):
    from app.pipeline import analyze as run_analyze

    r = await run_analyze(make_req(image_b64, user_note=note), NaiveClient(0.0))
    assert r.safety.blocked and r.risk_level != "allowed"


async def test_classify_invalid_output_falls_back_to_warn_only(image_b64):
    from app.errors import ModelOutputError

    class Broken(MockClient):
        async def classify(self, req):
            raise ModelOutputError("x")

    r = await analyze(make_req(image_b64), Broken(0.0))
    assert r.risk_level == "warn_only" and r.safety.blocked


async def test_sam_outage_falls_back_to_text_without_invented_segments(image_b64):
    from app.errors import AppError

    class MissingSam(MockClient):
        async def segment(self, *args):
            raise AppError("upstream_error", "offline", 502)

    r = await analyze(make_req(image_b64, mock_scenario="textile_tear"), MissingSam(0))
    assert r.segments == [] and r.guide.steps
    assert all(s.overlay is None and s.segment_ids == [] for s in r.guide.steps)


async def test_sam_budget_error_is_never_swallowed(image_b64):
    from app.errors import BudgetExceeded

    class OverBudget(MockClient):
        async def segment(self, *args):
            raise BudgetExceeded(0.1)

    with pytest.raises(BudgetExceeded):
        await analyze(make_req(image_b64, mock_scenario="textile_tear"), OverBudget(0))


async def test_followup_battery_disclosure_blocks_guide(image_b64):
    r = await analyze(
        make_req(
            image_b64, mock_scenario="textile_tear", answers=[{"question_id": "q1", "text": "Die Jacke hat einen Akku"}]
        ),
        NaiveClient(0),
    )
    assert r.safety.blocked and r.guide.steps == []


@pytest.mark.parametrize("failure", ["upstream_error", "model_output_invalid", "budget_exceeded"])
async def test_grounding_failures_keep_parts_and_budget_errors_propagate(image_b64, failure):
    from app.errors import AppError, BudgetExceeded, ModelOutputError

    class BrokenGrounding(MockClient):
        async def ground(self, *args):
            if failure == "budget_exceeded":
                raise BudgetExceeded(0.1)
            if failure == "model_output_invalid":
                raise ModelOutputError("invalid box")
            raise AppError("upstream_error", "offline", 502)

    req = make_req(image_b64, mock_scenario="textile_grounding")
    if failure == "budget_exceeded":
        with pytest.raises(BudgetExceeded):
            await analyze(req, BrokenGrounding(0))
    else:
        result = await analyze(req, BrokenGrounding(0))
        assert len(result.segments) == 1 and result.segments[0].kind == "part"
        assert result.instances == {} and result.diagnosis.evidence_segment_ids == []


@pytest.mark.parametrize("scenario", ["textile_tear", "battery_jacket"])
async def test_grounding_never_runs_for_damage_matches_or_blocked_cases(image_b64, scenario):
    class NoGrounding(MockClient):
        async def ground(self, *args):
            pytest.fail("grounding must not run")

    await analyze(make_req(image_b64, mock_scenario=scenario), NoGrounding(0))
