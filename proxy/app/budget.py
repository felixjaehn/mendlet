"""Per-day API cost guard, persisted in a small JSON file."""

import json
import os
import threading
from collections.abc import Callable
from datetime import date
from pathlib import Path

from .errors import BudgetExceeded

MUSE_IN_PER_TOKEN = 1.25 / 1_000_000
MUSE_OUT_PER_TOKEN = 4.25 / 1_000_000
# Muse Wonder 1.0, Standard mode (Contributor mode not available). Primary source:
# https://dev.meta.ai/docs/pricing-rate-limits (read 2026-10-28): $4.00 / $20.00 / $0.20 (cached input) per 1M tokens.
WONDER_IN_PER_TOKEN = 4.00 / 1_000_000
WONDER_OUT_PER_TOKEN = 20.00 / 1_000_000
WONDER_CACHED_IN_PER_TOKEN = 0.20 / 1_000_000
SAM_PER_IMAGE = 2.50 / 1000
SAM_PER_FRAME = 0.20 / 1000
MUSE_IMAGE_PER_IMAGE = 0.01
TRANSCRIBE_PER_HOUR = 0.18


def muse_cost(input_tokens: int, output_tokens: int) -> float:
    return input_tokens * MUSE_IN_PER_TOKEN + output_tokens * MUSE_OUT_PER_TOKEN


def wonder_cost(input_tokens: int, output_tokens: int, cached_tokens: int = 0) -> float:
    cached = min(max(cached_tokens, 0), input_tokens)
    return (
        (input_tokens - cached) * WONDER_IN_PER_TOKEN
        + cached * WONDER_CACHED_IN_PER_TOKEN
        + output_tokens * WONDER_OUT_PER_TOKEN
    )


def sam_cost(images: int) -> float:
    return images * SAM_PER_IMAGE


def sam_video_cost(frames: int) -> float:
    return max(50, frames) * SAM_PER_FRAME


def image_cost(images: int = 1) -> float:
    return images * MUSE_IMAGE_PER_IMAGE


class Budget:
    def __init__(
        self,
        path: Path,
        limit_usd: float,
        today: Callable[[], str] = lambda: date.today().isoformat(),
    ) -> None:
        self.path = path
        self.limit_usd = limit_usd
        self._today = today
        self._lock = threading.Lock()

    def _read(self) -> float:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            return float(data["spent_usd"]) if data.get("date") == self._today() else 0.0
        except (OSError, ValueError, KeyError, TypeError):
            return 0.0

    def spent_today(self) -> float:
        with self._lock:
            return self._read()

    def check(self) -> None:
        if self.spent_today() >= self.limit_usd:
            raise BudgetExceeded(self.limit_usd)

    def add(self, cost_usd: float) -> None:
        with self._lock:
            total = self._read() + max(0.0, cost_usd)
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(json.dumps({"date": self._today(), "spent_usd": round(total, 6)}), encoding="utf-8")
            os.replace(tmp, self.path)


def transcribe_cost(seconds: float) -> float:
    return seconds / 3600 * TRANSCRIBE_PER_HOUR
