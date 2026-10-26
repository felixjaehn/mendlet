"""Dev cache for real-mode model calls (so tests/benchmark never re-spend credits)."""

import hashlib
import json
from pathlib import Path
from typing import Any


class ModelCache:
    def __init__(self, directory: Path, enabled: bool) -> None:
        self.dir = directory / "model_calls"
        self.enabled = enabled

    @staticmethod
    def key(*parts: Any) -> str:
        blob = json.dumps(parts, sort_keys=True, ensure_ascii=False, default=str)
        return hashlib.sha256(blob.encode("utf-8")).hexdigest()

    def get(self, key: str) -> str | None:
        if not self.enabled:
            return None
        try:
            return json.loads((self.dir / f"{key}.json").read_text(encoding="utf-8"))["text"]
        except (OSError, ValueError, KeyError):
            return None

    def set(self, key: str, text: str) -> None:
        if not self.enabled:
            return
        self.dir.mkdir(parents=True, exist_ok=True)
        (self.dir / f"{key}.json").write_text(json.dumps({"text": text}, ensure_ascii=False), encoding="utf-8")
