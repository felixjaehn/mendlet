import pytest

from app.errors import ModelOutputError
from app.models import ClassifyResult, DiagnosePlan
from app.mock_data import textile_tear
from app.parsing import call_validated, parse_model_json

GOOD = '{"category":"textile","risk_level":"allowed","reason":"Jeans"}'


def test_parses_valid_and_fenced_json():
    assert parse_model_json(GOOD, ClassifyResult).category == "textile"
    assert parse_model_json(f"```json\n{GOOD}\n```", ClassifyResult).risk_level == "allowed"
    assert parse_model_json(f"Hier: {GOOD} Fertig.", ClassifyResult).reason == "Jeans"


@pytest.mark.parametrize("bad", [
    "kein json",
    '{"category":"textile"',
    '{"category":"bike","risk_level":"allowed","reason":"x"}',
    '{"category":"textile","risk_level":"maybe","reason":"x"}',
    '{"category":"textile","risk_level":"allowed"}',
])
def test_invalid_raises(bad):
    with pytest.raises(ModelOutputError):
        parse_model_json(bad, ClassifyResult)


def _caller(answers):
    calls = []

    async def call():
        calls.append(1)
        return answers[len(calls) - 1]

    return call, calls


async def test_valid_first_try_no_retry():
    call, calls = _caller([GOOD])
    obj, _ = await call_validated(call, ClassifyResult)
    assert obj.category == "textile" and len(calls) == 1


async def test_single_retry_recovers():
    call, calls = _caller(["oops", GOOD])
    obj, raw = await call_validated(call, ClassifyResult)
    assert obj.category == "textile" and raw == GOOD and len(calls) == 2


async def test_exactly_one_retry_then_clean_error():
    call, calls = _caller(["oops", "still bad", GOOD])
    with pytest.raises(ModelOutputError) as exc:
        await call_validated(call, ClassifyResult)
    assert len(calls) == 2
    assert exc.value.status == 502 and exc.value.code == "model_output_invalid"


def test_diagnose_plan_roundtrip():
    plan = textile_tear()
    again = parse_model_json(plan.model_dump_json(), DiagnosePlan)
    assert again == plan
