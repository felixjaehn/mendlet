import io
import wave

import pytest

from app.audio import ensure_wav
from app.errors import AppError
from tests.test_api import wav_bytes


@pytest.mark.parametrize("rate", [16000, 24000])
def test_supported_audio_passes_unchanged(rate):
    raw = wav_bytes(rate=rate)
    wav, duration = ensure_wav(raw)
    assert wav == raw and duration == pytest.approx(0.2)


@pytest.mark.parametrize("raw", [wav_bytes(seconds=0), wav_bytes()[:-2], b"RIFF\x00\x00\x00\x00WAVE"])
def test_empty_or_truncated_audio_is_rejected(raw):
    with pytest.raises(AppError) as exc:
        ensure_wav(raw)
    assert exc.value.code == "unsupported_audio"


def test_over_ten_minutes_is_rejected():
    with pytest.raises(AppError) as exc:
        ensure_wav(wav_bytes(seconds=600.01))
    assert exc.value.code == "audio_too_long"


def test_non_pcm_width_rejected():
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(16000)
        w.writeframes(b"\x80" * 160)
    with pytest.raises(AppError):
        ensure_wav(buf.getvalue())
