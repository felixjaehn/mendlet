"""Settings from environment variables (optionally a local .env file)."""

import os
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path

PROXY_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = PROXY_DIR.parent


def _truthy(value: str | None) -> bool | None:
    if value is None or value.strip() == "":
        return None
    return value.strip().lower() in {"1", "true", "yes", "on"}


def load_dotenv(path: Path) -> None:
    """Minimal .env loader. Never overrides variables that are already set."""
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


@dataclass(frozen=True)
class Settings:
    meta_api_key: str = ""
    base_url: str = "https://api.meta.ai/v1"
    muse_model: str = "muse-spark-1.3"
    sam_model: str = "sam-3.1"
    transcribe_model: str = "muse-voice-transcribe-1.0"
    daily_budget_usd: float = 5.0
    mock_mode: bool = True
    cache_model_calls: bool = False
    cache_dir: Path = field(default_factory=lambda: PROXY_DIR / ".cache")
    prompts_dir: Path = field(default_factory=lambda: REPO_DIR / "prompts")
    mock_delay_scale: float = 1.0

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "Settings":
        e = os.environ if env is None else env
        key = e.get("META_API_KEY", "").strip()
        explicit = _truthy(e.get("MOCK_MODE"))
        return cls(
            meta_api_key=key,
            base_url=e.get("META_BASE_URL", "https://api.meta.ai/v1"),
            muse_model=e.get("MUSE_MODEL") or "muse-spark-1.3",
            sam_model=e.get("SAM_MODEL") or "sam-3.1",
            transcribe_model=e.get("TRANSCRIBE_MODEL") or "muse-voice-transcribe-1.0",
            daily_budget_usd=float(e.get("DAILY_BUDGET_USD") or 5.0),
            mock_mode=explicit if explicit is not None else not key,
            cache_model_calls=bool(_truthy(e.get("CACHE_MODEL_CALLS"))),
            cache_dir=Path(e.get("CACHE_DIR") or PROXY_DIR / ".cache"),
            prompts_dir=Path(e.get("PROMPTS_DIR") or REPO_DIR / "prompts"),
            mock_delay_scale=float(e.get("MOCK_DELAY_SCALE") or 1.0),
        )
