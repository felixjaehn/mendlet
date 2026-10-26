"""Strict validation of model answers with exactly one retry."""

import json
import re
from collections.abc import Awaitable, Callable
from typing import TypeVar

from pydantic import BaseModel, ValidationError

from .errors import ModelOutputError

T = TypeVar("T", bound=BaseModel)

_FENCE = re.compile(r"^```(?:json)?\s*|\s*```$", re.IGNORECASE)


def extract_json(text: str) -> str:
    text = _FENCE.sub("", text.strip())
    if text.startswith("{"):
        return text
    start, end = text.find("{"), text.rfind("}")
    return text[start : end + 1] if start != -1 and end > start else text


def parse_model_json(text: str, cls: type[T]) -> T:
    try:
        data = json.loads(extract_json(text))
    except json.JSONDecodeError as exc:
        raise ModelOutputError("invalid JSON") from exc
    try:
        return cls.model_validate(data)
    except ValidationError as exc:
        locs = ", ".join(".".join(map(str, e["loc"])) for e in exc.errors()[:5])
        raise ModelOutputError(f"schema violation at: {locs}") from exc


async def call_validated(
    call: Callable[[], Awaitable[str]], cls: type[T], retries: int = 1
) -> tuple[T, str]:
    """Call the model, validate; on invalid output retry exactly `retries` time(s)."""
    error: ModelOutputError | None = None
    for _ in range(retries + 1):
        text = await call()
        try:
            return parse_model_json(text, cls), text
        except ModelOutputError as exc:
            error = exc
    assert error is not None
    raise error
