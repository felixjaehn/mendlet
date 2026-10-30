import json

import pytest

from app.budget import Budget, image_cost, muse_cost, sam_cost, sam_video_cost, transcribe_cost
from app.cache import ModelCache
from app.errors import BudgetExceeded
from app.prompts import MARKER, PROMPTS, load_prompt, schema_text


def test_prices():
    assert muse_cost(1_000_000, 0) == pytest.approx(1.25)
    assert muse_cost(0, 1_000_000) == pytest.approx(4.25)
    assert sam_cost(1000) == pytest.approx(2.5)
    assert transcribe_cost(3600) == pytest.approx(0.18)
    assert image_cost() == pytest.approx(0.01)
    assert sam_video_cost(10) == pytest.approx(0.01)
    assert sam_video_cost(1000) == pytest.approx(0.2)


def test_budget_limit_and_persistence(tmp_path):
    p = tmp_path / "b.json"
    b = Budget(p, 1.0, today=lambda: "2026-10-26")
    b.check()
    b.add(0.6)
    b.check()
    b.add(0.5)
    with pytest.raises(BudgetExceeded) as e:
        Budget(p, 1.0, today=lambda: "2026-10-26").check()  # persisted across instances
    assert e.value.status == 429
    Budget(p, 1.0, today=lambda: "2026-10-27").check()  # new day resets
    assert json.loads(p.read_text())["spent_usd"] == pytest.approx(1.1)


def test_cache_roundtrip(tmp_path):
    c = ModelCache(tmp_path, True)
    k = ModelCache.key("v1", "m", "input")
    assert c.get(k) is None
    c.set(k, '{"a":1}')
    assert c.get(k) == '{"a":1}'
    assert k != ModelCache.key("v2", "m", "input")
    off = ModelCache(tmp_path, False)
    assert off.get(k) is None


@pytest.mark.parametrize("key", list(PROMPTS))
def test_prompt_files_have_current_schema(key):
    text = load_prompt(key)
    assert text.endswith(MARKER.strip("\n") + "\n" + schema_text(PROMPTS[key][2]))
    schema = text.split(MARKER.strip("\n") + "\n")[1]
    assert "$ref" not in schema and "$defs" not in schema


def test_schema_preserves_actual_title_property():
    from app.models import DiagnosePlan
    from app.prompts import inline_schema, prompt_version

    step = inline_schema(DiagnosePlan)["properties"]["guide"]["properties"]["steps"]["items"]
    assert step["properties"]["title"] == {"type": "string"}
    assert set(step["required"]) <= set(step["properties"])
    assert prompt_version("diagnose") == "v9"


def test_prompt_b_v3_label_and_safety_rules():
    """Live 2026-10-28: v2 asked for the label on obvious denim and flagged every sewing step as safety-critical."""
    from app.config import Settings
    from app.prompts import load_prompt

    text = load_prompt("diagnose", Settings.from_env({}).prompts_dir)
    assert "NICHT routinemäßig nach dem Etikett" in text
    assert "Normales Nähen mit der Handnadel" in text
