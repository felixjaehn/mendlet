"""WAV normalisation for Muse Voice Transcribe (mono, 16-bit PCM, 16 or 24 kHz only)."""

import io
import wave

import numpy as np

from .errors import AppError

MAX_BYTES = 32_000_000  # documented body limit; leave room for multipart headers
MAX_SECONDS = 600


def _unsupported(msg: str, en: str) -> AppError:
    return AppError("unsupported_audio", msg, 415, en)


def ensure_wav(data: bytes) -> tuple[bytes, float]:
    """Return (WAV bytes ready for the API, duration in seconds).

    Accepts any 16-bit PCM WAV: downmixes to mono and resamples to 16 kHz if needed.
    Other containers (m4a, webm, ...) are rejected with 415.
    """
    if len(data) > MAX_BYTES:
        raise AppError(
            "audio_too_large",
            "Die Audiodatei ist zu groß (maximal 32 MB).",
            413,
            en="The audio file is too large (32 MB maximum).",
        )
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise _unsupported(
            "Nur RIFF/WAVE mit 16-Bit-PCM wird unterstützt.", "Only RIFF/WAVE with 16-bit PCM is supported."
        )
    try:
        with wave.open(io.BytesIO(data)) as w:
            channels, width, rate, frames = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
            raw = w.readframes(frames)
    except (wave.Error, EOFError) as exc:
        raise _unsupported(
            "Nur WAV wird unterstützt (mono, 16 Bit, 16 kHz). Bitte als WAV aufnehmen.",
            "Only WAV is supported (mono, 16 bit, 16 kHz). Please record as WAV.",
        ) from exc
    if width != 2 or channels < 1 or rate < 1:
        raise _unsupported("Nur 16-Bit-PCM-WAV wird unterstützt.", "Only 16-bit PCM WAV is supported.")
    if not frames or len(raw) != frames * channels * width:
        raise _unsupported("Die WAV-Aufnahme ist leer oder unvollständig.", "The WAV recording is empty or incomplete.")
    duration = frames / rate if rate else 0.0
    if duration > MAX_SECONDS:
        raise AppError(
            "audio_too_long",
            "Die Aufnahme ist länger als 10 Minuten.",
            400,
            en="The recording is longer than 10 minutes.",
        )
    if channels == 1 and rate in (16000, 24000):
        # Canonicalize RIFF too: remove metadata/trailing chunks and guarantee a
        # small multipart body (max 600s * 24000 * 2 bytes, plus WAV headers).
        out = io.BytesIO()
        with wave.open(out, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(raw)
        return out.getvalue(), duration

    samples = np.frombuffer(raw, dtype="<i2").astype(np.float32)
    if channels > 1:
        samples = samples[: len(samples) // channels * channels].reshape(-1, channels).mean(axis=1)
    target = rate if rate in (16000, 24000) else 16000
    if target != rate and len(samples):
        n = int(len(samples) * target / rate)
        samples = np.interp(np.linspace(0, len(samples) - 1, n), np.arange(len(samples)), samples)
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(target)
        w.writeframes(np.clip(samples, -32768, 32767).astype("<i2").tobytes())
    return out.getvalue(), duration
