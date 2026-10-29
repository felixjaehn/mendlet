"""Electronics outlook (solder pads with polarity): prompts, pad grounding wire, pipeline merge, safety, mock."""
import json
import uuid

import pytest

from app import mock_electronics, safety
from app.models import AnalyzeResponse, Safety
from app.pipeline import analyze
from app.sam import PROMPT_META, SEGMENT_PROMPTS
from tests.conftest import make_image_b64, make_req
from tests.test_wire_contracts import SAM, chat_response, client_for, prepare_request, sam_response

EL = "low_voltage_electronics"
CLASSIFY_EL = {"category": EL, "risk_level": "allowed", "reason": "USB-Platine"}


def pad(label, box):
    return {"label": label, "box_0_1000": box}


PADS = {"pads": [pad("+", [100, 200, 400, 500]), pad("-", [500, 200, 800, 500]), pad("other", [100, 600, 300, 800])]}


def electronics_handler(seen, sam_text_for=lambda prompt: "", pads=PADS):
    def handler(req):
        data = json.loads(req.content)
        seen.append(data)
        if req.url.path == "/v1/responses":
            prompt = data["input"][0]["content"][0]["text"]
            if prompt.startswith("<0f>"):
                return sam_response(SAM.read_text().replace("<0f>7", "<0f>1"))
            return sam_response(sam_text_for(prompt))
        name = data["response_format"]["json_schema"]["name"]
        if name == "pad_grounding":
            return chat_response(pads)
        if name == "classify":
            return chat_response(CLASSIFY_EL)
        return chat_response(mock_electronics.plan().model_dump())
    return handler


def test_prompts_and_meta():
    assert SEGMENT_PROMPTS[EL] == ["red wire", "black wire", "copper wire strands", "circuit board"]
    assert PROMPT_META["red wire"] == ("Rotes Kabel", "part")
    assert PROMPT_META["black wire"] == ("Schwarzes Kabel", "part")
    assert PROMPT_META["copper wire strands"] == ("Abisoliertes Kabelende", "damage")
    assert PROMPT_META["circuit board"] == ("Platine", "part")


async def test_ground_pads_wire_to_segments_with_polarity(tmp_path):
    seen = []
    c = client_for(tmp_path, electronics_handler(seen))
    try:
        req = prepare_request(make_req(make_image_b64((640, 480)), note="USB-Lampe"))
        segs = await c.ground(req, EL)
        assert [s.label for s in segs] == ["Lötpad +", "Lötpad −", "Lötpad"]
        assert [s.polarity for s in segs] == ["+", "-", None]
        assert [s.id for s in segs] == ["seg_1", "seg_2", "seg_3"]
        assert all(s.kind == "part" and s.source == "grounding" and s.prompt == "solder pad" and s.mask for s in segs)
        # one Spark call, then one geometric SAM box prompt per pad (box from the 0-1000 grid)
        spark = [d for d in seen if "response_format" in d]
        assert len(spark) == 1 and "'+' or '-'" in spark[0]["messages"][0]["content"]
        prompts = [d["input"][0]["content"][0]["text"] for d in seen if "input" in d]
        assert len(prompts) == 3 and all(p.startswith("<0f>1<|box;") for p in prompts)
        assert "x1=64;y1=96;x2=255;y2=239" in prompts[0]
        calls = len(seen)
        await c.ground(req, EL)
        assert len(seen) == calls  # cached replay
    finally:
        await c.aclose()


async def test_ground_pads_none_visible_and_no_mask(tmp_path):
    seen = []
    c = client_for(tmp_path, electronics_handler(seen, pads={"pads": []}))
    try:
        req = prepare_request(make_req(make_image_b64((640, 480))))
        assert await c.ground(req, EL) == []
        assert not [d for d in seen if "input" in d]
    finally:
        await c.aclose()


async def test_pipeline_merges_text_segments_and_pads_even_with_damage(tmp_path):
    seen, events = [], []
    # SAM text finds the bare wire end (damage) - pads must still be grounded and merged.
    c = client_for(tmp_path, electronics_handler(seen, lambda p: SAM.read_text() if p == "copper wire strands" else ""))
    async def progress(stage):
        events.append(stage)
    async def grounding():
        events.append("grounding")
    try:
        req = prepare_request(make_req(make_image_b64((640, 480)), note="USB-Lampe ohne Funktion"))
        r = await analyze(req, c, progress, grounding)
        assert r.category == EL and not r.safety.blocked
        assert "grounding" in events
        sources = [s.source for s in r.segments]
        assert sources[0] == "text" and sources.count("grounding") == 3
        assert any(s.kind == "damage" and s.label == "Abisoliertes Kabelende" for s in r.segments)
        assert {s.polarity for s in r.segments} == {None, "+", "-"}
        assert [s.id for s in r.segments] == [f"seg_{i}" for i in range(1, len(r.segments) + 1)]
    finally:
        await c.aclose()


# ---- safety.enforce -------------------------------------------------------


def el_resp(category=EL) -> AnalyzeResponse:
    plan = mock_electronics.plan()
    return AnalyzeResponse(case_id=str(uuid.uuid4()), category=category, risk_level="allowed", safety=Safety(),
                           segments=mock_electronics.segments(), diagnosis=plan.diagnosis, decision=plan.decision,
                           shopping_list=plan.shopping_list, guide=plan.guide)


def solder_steps(r):
    return [s for s in r.guide.steps if s.overlay is not None and s.overlay.type == "solder"]


def test_enforce_keeps_valid_solder_overlays_and_forces_safety_critical():
    r = el_resp()
    for s in solder_steps(r):
        s.safety_critical = False
    out = safety.enforce(r, has_answers=True)
    steps = [s for s in out.guide.steps if s.overlay and s.overlay.type == "solder"]
    assert len(steps) == 2
    for s in steps:
        assert s.safety_critical and s.requires_confirmation
        assert s.overlay.from_segment_id in s.segment_ids and s.overlay.to_segment_id in s.segment_ids


def test_enforce_drops_overlay_when_pad_has_no_polarity():
    r = el_resp()
    for seg in r.segments:
        if seg.id == "seg_6":
            seg.polarity = None
    out = safety.enforce(r, has_answers=True)
    assert [s.n for s in out.guide.steps if s.overlay and s.overlay.type == "solder"] == [5]
    # the step itself stays, and is still safety critical
    step4 = next(s for s in out.guide.steps if s.title.startswith("Rotes"))
    assert step4.overlay is None and step4.safety_critical


def test_enforce_drops_overlay_when_from_segment_is_not_copper_strands():
    r = el_resp()
    for seg in r.segments:
        if seg.id == "seg_3":
            seg.prompt = "red wire"
    out = safety.enforce(r, has_answers=True)
    assert [s.overlay.to_segment_id for s in out.guide.steps if s.overlay] == ["seg_7"]


def test_enforce_drops_pad_that_is_not_grounded():
    r = el_resp()
    for seg in r.segments:
        if seg.id == "seg_7":
            seg.source = "text"
    out = safety.enforce(r, has_answers=True)
    assert [s.overlay.to_segment_id for s in out.guide.steps if s.overlay] == ["seg_6"]


def test_enforce_drops_solder_overlay_outside_electronics():
    out = safety.enforce(el_resp("textile"), has_answers=True)
    assert not [s for s in out.guide.steps if s.overlay and s.overlay.type == "solder"]


def test_enforce_drops_overlay_with_unknown_segment():
    r = el_resp()
    r.segments = [s for s in r.segments if s.id != "seg_6"]
    out = safety.enforce(r, has_answers=True)
    assert [s.overlay.to_segment_id for s in out.guide.steps if s.overlay] == ["seg_7"]


# ---- mock scenario --------------------------------------------------------


@pytest.mark.parametrize("kw", [{"mock_scenario": "electronics_wire"}, {"user_note": "USB Platine Kabel ab"}])
async def test_mock_electronics_wire_returns_solder_overlays(image_b64, kw):
    from app.mock_client import MockClient
    r = await analyze(make_req(image_b64, **kw), MockClient(0.0))
    assert r.category == EL and not r.safety.blocked
    solder = solder_steps(r)
    assert len(solder) == 2
    pads = {s.id: s for s in r.segments}
    assert [pads[s.overlay.to_segment_id].polarity for s in solder] == ["+", "-"]
    assert all(s.overlay.hold_seconds in (2, 3) and s.safety_critical and s.requires_confirmation for s in solder)
