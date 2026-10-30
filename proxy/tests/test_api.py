import base64
import io
import json
import wave

import pytest
from fastapi.testclient import TestClient

from app.budget import Budget
from app.main import create_app
from tests.conftest import make_image_b64


def parse_sse(text: str) -> list[tuple[str, dict]]:
    events = []
    for block in text.strip().split("\n\n"):
        lines = dict(ln.split(": ", 1) for ln in block.splitlines())
        events.append((lines["event"], json.loads(lines["data"])))
    return events


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200 and r.json()["status"] == "ok" and r.json()["mode"] == "mock"


def test_analyze_stream_stages_in_order_then_result(client, image_b64):
    with client.stream("POST", "/analyze", json={"image_base64": image_b64, "mock_scenario": "textile_tear"}) as r:
        assert r.headers["content-type"].startswith("text/event-stream")
        body = "".join(r.iter_text())
    events = parse_sse(body)
    names = [e for e, _ in events]
    assert names == ["progress", "progress", "segments", "progress", "progress", "result"]
    assert [d["stage"] for e, d in events if e == "progress"] == ["classify", "segment", "diagnose", "plan"]
    # early segments event carries exactly the final result's segments (same ids and JSON)
    assert events[2][1] == {"segments": events[-1][1]["segments"]}
    assert all(d["label"] for e, d in events if e == "progress")
    result = events[-1][1]
    assert result["category"] == "textile" and result["guide"]["steps"]


def test_analyze_stream_false_json(client, image_b64):
    r = client.post("/analyze?stream=false", json={"image_base64": image_b64, "user_note": "Akku"})
    assert r.status_code == 200
    assert r.json()["safety"]["blocked"] is True


def test_analyze_invalid_image_422(client):
    r = client.post("/analyze?stream=false", json={"image_base64": "AAAA"})
    assert r.status_code == 422 and r.json()["error"]["code"] == "invalid_image"


def test_large_image_downscaled(settings):
    from PIL import Image

    from app.images import downscale_b64

    big = make_image_b64((3000, 2000))
    out = Image.open(io.BytesIO(base64.b64decode(downscale_b64(big))))
    assert max(out.size) == 1536


def test_budget_429(settings):
    budget = Budget(settings.cache_dir / "b.json", 1.0)
    budget.add(1.5)
    c = TestClient(create_app(settings, budget=budget))
    r = c.post("/analyze?stream=false", json={"image_base64": make_image_b64()})
    assert r.status_code == 429
    assert "Tageslimit" in r.json()["error"]["message"]
    with c.stream("POST", "/analyze", json={"image_base64": make_image_b64()}) as r2:
        assert r2.status_code == 429


def test_step_help(client):
    body = {
        "step": {"n": 3, "title": "Kleber auftragen", "text": "t"},
        "diagnosis_summary": "s",
        "risk_level": "allowed",
        "issue_text": "Der Kleber haftet nicht",
    }
    r = client.post("/step-help", json=body)
    assert r.status_code == 200 and r.json()["escalate"] is False and r.json()["answer"]
    for word in ["Rauch", "heiß", "Akku", "brennt"]:
        r = client.post("/step-help", json={**body, "issue_text": f"Da ist {word}"})
        assert r.json()["escalate"] is True
    r = client.post("/step-help", json={**body, "risk_level": "warn_only"})
    assert r.json()["escalate"] is True


def wav_bytes(rate=16000, channels=1, seconds=0.2) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"\x00\x01" * int(rate * seconds) * channels)
    return buf.getvalue()


def test_transcribe_mock(client):
    r = client.post("/transcribe", files={"file": ("a.wav", wav_bytes(), "audio/wav")})
    assert r.status_code == 200 and r.json()["text"]


def test_transcribe_rejects_non_wav(client):
    r = client.post("/transcribe", files={"file": ("a.m4a", b"not a wav", "audio/mp4")})
    assert r.status_code == 415


def test_ensure_wav_converts_stereo_44k():
    from app.audio import ensure_wav

    out, dur = ensure_wav(wav_bytes(44100, 2))
    with wave.open(io.BytesIO(out)) as w:
        assert (w.getnchannels(), w.getframerate(), w.getsampwidth()) == (1, 16000, 2)
    assert dur == pytest.approx(0.2, abs=0.01)


def test_more_than_50_images_rejected_before_any_model_call(client, image_b64):
    r = client.post(
        "/analyze?stream=false",
        json={"image_base64": image_b64, "extra_images": [{"purpose": "other", "image_base64": image_b64}] * 50},
    )
    assert r.status_code == 422
