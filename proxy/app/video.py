"""Bounded inline MP4 validation; no media is written to disk."""

import base64
import binascii

from .errors import AppError


def prepare_video(b64: str) -> str:
    if b64.startswith("data:video/mp4;base64,"):
        b64 = b64.split(",", 1)[1]
    try:
        raw = base64.b64decode(b64, validate=True)
    except (ValueError, binascii.Error) as exc:
        raise AppError("invalid_video", "Das Video konnte nicht gelesen werden. Bitte sende eine MP4-Datei.", 422) from exc
    if len(raw) > 50_000_000:
        raise AppError("invalid_video", "Das Video darf höchstens 50 MB groß sein.", 413)
    # ISO Base Media File Format header, not a full codec/playability check.
    if len(raw) < 16 or raw[4:8] != b"ftyp" or not 16 <= int.from_bytes(raw[:4], "big") <= len(raw):
        raise AppError("invalid_video", "Das Video konnte nicht gelesen werden. Bitte sende eine MP4-Datei.", 422)
    return base64.b64encode(raw).decode("ascii")
