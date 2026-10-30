"""Locale handling: "en" yields English labels, stage labels, safety texts and prompt language; "de" is unchanged."""

import json

import pytest

from app import i18n, safety
from app.agent import WonderAgent
from app.errors import AppError, BudgetExceeded
from app.mock_client import MockClient
from app.pipeline import analyze, stage_label
from app.config import REPO_DIR
from app.prompts import load_prompt, prompt_version
from tests.conftest import make_req


def sse_events(client, body):
    events = []
    with client.stream("POST", "/analyze", json=body) as r:
        for block in r.read().decode().strip().split("\n\n"):
            event, data = block.split("\n", 1)
            events.append((event.removeprefix("event: "), json.loads(data.removeprefix("data: "))))
    return events


def test_norm_falls_back_to_german():
    assert [i18n.norm(x) for x in ("en", "en-US", "EN_gb", "de", "de-AT", "fr", "", None)] == \
        ["en", "en", "en", "de", "de", "de", "de", "de"]


def test_prompt_versions_and_language_placeholder():
    assert prompt_version("diagnose") == "v8"
    en, de = load_prompt("diagnose", locale="en"), load_prompt("diagnose", locale="de")
    assert "Write all user-facing texts in English" in en
    assert "Write all user-facing texts in German" in de
    assert "{language}" not in en and "{estimate_note}" not in en
    assert 'estimate_note="Estimate"' in en and 'estimate_note="Schätzung"' in de
    # default stays German, v4 is kept untouched
    assert load_prompt("diagnose") == de
    assert "Alle Texte sind auf Deutsch" in (REPO_DIR / "prompts" / "prompt_b_diagnose.v4.txt").read_text(encoding="utf-8")
    for key in ("classify", "step_help"):
        assert "Write" in load_prompt(key, locale="en") and "English" in load_prompt(key, locale="en")
        assert "German" in load_prompt(key, locale="de")


async def test_pipeline_labels_and_estimate_note_in_english(image_b64):
    c = MockClient(0.0)
    de = await analyze(make_req(image_b64, mock_scenario="textile_tear"), c)
    en = await analyze(make_req(image_b64, mock_scenario="textile_tear", locale="en"), c)
    assert [s.id for s in de.segments] == [s.id for s in en.segments]
    assert any(s.label == "Riss" for s in de.segments) and not any(s.label == "Riss" for s in en.segments)
    assert any(s.label == "Tear" for s in en.segments)
    assert de.decision.estimate_note == "Schätzung"
    assert en.decision.estimate_note == "Estimate"


def test_stage_labels_in_sse(client, image_b64):
    de = sse_events(client, {"image_base64": image_b64, "mock_scenario": "textile_tear"})
    en = sse_events(client, {"image_base64": image_b64, "mock_scenario": "textile_tear", "locale": "en"})
    label = lambda events, stage: next(d["label"] for e, d in events if e == "progress" and d["stage"] == stage)  # noqa: E731
    assert label(de, "classify") == "Objekt und Risiko prüfen"
    assert label(en, "classify") == "Checking object and risk"
    assert [label(en, s) for s in ("segment", "diagnose", "plan")] == [stage_label(s, "en") for s in ("segment", "diagnose", "plan")]
    assert all("Schadstelle" not in l for l in i18n.STAGE_LABELS["en"].values())


async def test_blocked_reason_in_english_and_german(image_b64):
    c = MockClient(0.0)
    en = await analyze(make_req(image_b64, user_note="My heated jacket battery is broken", locale="en"), c)
    de = await analyze(make_req(image_b64, user_note="Akku am Ladegerät, Nutzer-Hinweis", locale="de",
                                mock_scenario="unsupported"), c)
    assert en.safety.blocked and de.safety.blocked
    assert "dangerous" in en.safety.reason and "Hint from your description: Battery" in en.safety.reason
    assert "gefährlich" in de.safety.reason and "Hinweis aus deiner Beschreibung" in de.safety.reason
    assert en.diagnosis.summary == en.safety.reason


def test_precheck_english_keywords_and_negated_battery():
    assert safety.precheck_note("a child car seat strap", "en").risk_level == "professional"
    assert safety.precheck_note("charger cable frayed", "en").risk_level == "warn_only"
    assert safety.precheck_note("there is no battery inside, just a tear", "en").risk_level == "allowed"
    assert safety.precheck_note("remains of a hem", "en").risk_level == "allowed"
    de = safety.precheck_note("Akku", None)
    assert de.reason.startswith("Dieser Gegenstand kann gefährlich sein")


def test_unsupported_reason_and_step_help(client, image_b64):
    assert safety.blocked_reason("unsupported", "allowed", None, "en").startswith("This object is not supported")
    assert safety.blocked_reason("unsupported", "allowed", None).startswith("Dieses Objekt wird nicht")
    body = {"step": {"n": 1, "title": "t", "text": "x"}, "diagnosis_summary": "s", "risk_level": "warn_only",
            "issue_text": "smoke"}
    assert client.post("/step-help", json={**body, "locale": "en"}).json()["answer"].startswith("There is no guide")
    assert client.post("/step-help", json=body).json()["answer"].startswith("Für diesen Fall")
    assert safety.step_help_escalation("it started to smoke", "allowed")


def test_error_messages_follow_locale(client):
    r = client.post("/analyze?stream=false", json={"image_base64": "AAAA", "locale": "en"})
    assert r.status_code == 422 and r.json()["error"]["message"] == "The image could not be read."
    r = client.post("/analyze?stream=false", json={"image_base64": "AAAA"})
    assert r.json()["error"]["message"] == "Das Bild konnte nicht gelesen werden."
    err = BudgetExceeded(5.0)
    assert "tomorrow" in err.localized("en") and "morgen" in err.localized("de")
    assert AppError("x", "nur deutsch").localized("en") == "nur deutsch"


def test_agent_trace_labels_by_locale():
    raw = json.dumps({"concept": "rip"})
    assert WonderAgent._describe("segment", raw, "m", "de")[0] == "SAM sucht „rip“"
    assert WonderAgent._describe("segment", raw, "m", "en")[0] == "SAM is looking for “rip”"
    assert WonderAgent._describe("finish", "{}", "m", "en")[0].startswith("Masks checked")


def test_relabel_covers_sam_prompt_labels():
    from app.sam import PROMPT_META
    assert all(label in i18n.LABELS_EN for label, _ in PROMPT_META.values())
    assert {i18n.label(l, "en") for l in ("Lötpad +", "Lötpad −", "Lötpad")} == {"Solder pad +", "Solder pad −", "Solder pad"}
    assert i18n.label("Riss", "de") == "Riss"
