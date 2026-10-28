"""Dev cache for real-mode model calls (so tests/benchmark never re-spend credits)."""

import hashlib
import json
import os
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
            value = json.loads((self.dir / f"{key}.json").read_text(encoding="utf-8"))["text"]
            return value if isinstance(value, str) else None
        except (OSError, ValueError, KeyError, TypeError):
            return None

    def set(self, key: str, text: str) -> None:
        if not self.enabled:
            return
        self.dir.mkdir(parents=True, exist_ok=True)
        path = self.dir / f"{key}.json"
        tmp = path.with_suffix(f".{os.getpid()}.tmp")
        fd = os.open(tmp, os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump({"text": text}, f, ensure_ascii=False)
        os.replace(tmp, path)
