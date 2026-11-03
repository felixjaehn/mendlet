from shutil import copytree

from app.budget import Budget
from app.clients import RealMetaClient
from app.config import Settings
from app.mock_data import textile_tear
from app.models import ClassifyResult
from app.prompts import PROMPTS, load_prompt
from tests.conftest import make_req

GOOD = '{"category":"shoe","risk_level":"allowed","reason":"Sneaker"}'


def make(tmp_path) -> RealMetaClient:
    s = Settings(meta_api_key="LLM_test", mock_mode=False, cache_model_calls=True, cache_dir=tmp_path)
    return RealMetaClient(s, Budget(tmp_path / "b.json", 5.0))


async def test_retry_once_and_cache(tmp_path, image_b64, monkeypatch):
    c = make(tmp_path)
    calls = []

    async def fake_chat(system, text, images, name, cls):
        calls.append(name)
        return "kaputt" if len(calls) == 1 else GOOD

    monkeypatch.setattr(c, "_chat", fake_chat)
    req = make_req(image_b64, user_note="Sohle")
    r = await c.classify(req)
    assert isinstance(r, ClassifyResult) and r.category == "shoe" and len(calls) == 2
    again = await c.classify(req)  # served from the dev cache, no model call
    assert again == r and len(calls) == 2


async def test_sam_one_call_per_prompt(tmp_path, image_b64, monkeypatch):
    c = make(tmp_path)
    seen = []

    async def fake_one(img, prompt, w, h):
        seen.append(prompt)
        return []

    monkeypatch.setattr(c, "_sam_one", fake_one)
    assert await c.segment(make_req(image_b64), "textile", ["tear", "hole", "open seam"]) == []
    assert sorted(seen) == ["hole", "open seam", "tear"]


async def test_diagnose_keeps_startup_prompt_after_file_is_removed(tmp_path, image_b64, monkeypatch):
    prompts_dir = tmp_path / "prompts"
    copytree(Settings().prompts_dir, prompts_dir)
    expected = load_prompt("diagnose", prompts_dir, "en")
    settings = Settings(meta_api_key="LLM_test", mock_mode=False, cache_dir=tmp_path, prompts_dir=prompts_dir)
    client = RealMetaClient(settings, Budget(tmp_path / "b.json", 5.0))
    (prompts_dir / PROMPTS["diagnose"][1]).unlink()
    plan = textile_tear()

    async def fake_chat(system, text, images, name, cls):
        assert name == "diagnose"
        assert system == expected
        return plan.model_dump_json()

    monkeypatch.setattr(client, "_chat", fake_chat)
    try:
        classification = ClassifyResult(category="textile", risk_level="allowed", reason="Knit hole")
        result = await client.diagnose(make_req(image_b64, locale="en-US"), classification, [])
        assert result == plan
    finally:
        await client.aclose()
