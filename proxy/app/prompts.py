"""Versioned prompt files + JSON schemas generated from the Pydantic models.

`python -m app.prompts --write` regenerates the schema block at the end of each prompt file.
"""

import json
import sys
from pathlib import Path
from typing import Any

from pydantic import BaseModel

from .config import REPO_DIR
from .models import ClassifyResult, DiagnosePlan, StepHelpResponse

MARKER = "\n\nJSON-Schema der Antwort (strikt einhalten, keine zusätzlichen Felder, kein Text außerhalb des JSON):\n"

PROMPTS: dict[str, tuple[str, str, type[BaseModel]]] = {
    # key: (version, file name, answer model)
    "classify": ("v1", "prompt_a_classify.v1.txt", ClassifyResult),
    "diagnose": ("v3", "prompt_b_diagnose.v3.txt", DiagnosePlan),
    "step_help": ("v1", "prompt_c_step_help.v1.txt", StepHelpResponse),
}


def inline_schema(cls: type[BaseModel]) -> dict[str, Any]:
    """JSON schema with all $ref inlined (no $defs, no recursion) and titles removed."""
    schema = cls.model_json_schema()
    defs = schema.pop("$defs", {})

    def walk(node: Any) -> Any:
        if isinstance(node, dict):
            if "$ref" in node:
                return walk(defs[node["$ref"].split("/")[-1]])
            return {
                k: ({name: walk(prop) for name, prop in v.items()} if k == "properties" else walk(v))
                for k, v in node.items() if k not in {"title", "default"}
            }
        if isinstance(node, list):
            return [walk(v) for v in node]
        return node

    return walk(schema)


def schema_text(cls: type[BaseModel]) -> str:
    return json.dumps(inline_schema(cls), ensure_ascii=False, separators=(",", ":"))


def prompt_version(key: str) -> str:
    return PROMPTS[key][0]


def load_prompt(key: str, prompts_dir: Path | None = None) -> str:
    _, name, _ = PROMPTS[key]
    return ((prompts_dir or REPO_DIR / "prompts") / name).read_text(encoding="utf-8").strip()


def write_schemas(prompts_dir: Path | None = None) -> None:
    for key, (_, name, cls) in PROMPTS.items():
        path = (prompts_dir or REPO_DIR / "prompts") / name
        body = path.read_text(encoding="utf-8").split(MARKER)[0].rstrip()
        path.write_text(body + MARKER + schema_text(cls) + "\n", encoding="utf-8")


if __name__ == "__main__":
    if "--write" in sys.argv:
        write_schemas()
