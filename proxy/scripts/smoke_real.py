"""One attempt per model, cached and offline-safe without META_API_KEY.

Deliberately does NOT run analyze(): that would make multiple billable Spark/SAM
calls. Spark uses bounded TEXT ONLY because api-notes.md gives no image token
ceiling. SAM uses the supplied image; ASR uses a <=5 second WAV or in-memory silence.
No dotenv loading, retries, redirects, cache-expiry or automatic retry of failures.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import fcntl
import hashlib
import io
import json
import os
import sys
import wave
from pathlib import Path

PROXY_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROXY_DIR))

from app.audio import ensure_wav  # noqa: E402
from app.budget import Budget, muse_cost, sam_cost, transcribe_cost  # noqa: E402
from app.cache import ModelCache  # noqa: E402
from app.clients import RealMetaClient  # noqa: E402
from app.config import Settings  # noqa: E402
from app.errors import AppError  # noqa: E402
from app.images import prepare_request  # noqa: E402
from app.models import AnalyzeRequest, ClassifyResult  # noqa: E402
from app.parsing import parse_model_json  # noqa: E402
from app.prompts import inline_schema, load_prompt  # noqa: E402

CAP_USD = 0.10  # fixed; not configurable through flags or environment
SPARK_INPUT_CEILING = 65_536  # intentionally very conservative for <=8 KiB of text/schema
SPARK_OUTPUT_LIMIT = 2048  # live 2026-10-28: ~820 reasoning tokens before JSON; 256 returned empty output
MAX_AUDIO_SECONDS = 5
RESERVATIONS = {
    "muse-spark-1.3": muse_cost(SPARK_INPUT_CEILING, SPARK_OUTPUT_LIMIT),
    "sam-3.1": sam_cost(1),
    "muse-voice-transcribe-1.0": transcribe_cost(MAX_AUDIO_SECONDS),
}
if sum(RESERVATIONS.values()) >= CAP_USD:
    raise RuntimeError("Invalid smoke reservations: fixed cap would be exceeded")


class SmokeState:
    """Process lock plus durable write-ahead reservations, including uncertain failures.

    One attempt per model per cache directory. Inputs must match on replay. A
    missing/corrupt model cache cannot cause a new request: the ledger owns replay.
    """

    def __init__(self, directory: Path):
        self.directory = directory
        self.path = directory / "attempts.json"
        self.lock_fd = None
        self.data = None

    def __enter__(self):
        self.directory.mkdir(parents=True, exist_ok=True)
        self.lock_fd = os.open(self.directory / "smoke.lock", os.O_CREAT | os.O_RDWR, 0o600)
        try:
            fcntl.flock(self.lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if self.path.exists():
                self.data = json.loads(self.path.read_text())
                if self.data["version"] != 1 or not isinstance(self.data["models"], dict):
                    raise ValueError("Invalid smoke ledger")
                for model, entry in self.data["models"].items():
                    if (
                        model not in RESERVATIONS
                        or entry["reserved_usd"] != RESERVATIONS[model]
                        or entry["status"] not in {"started", "pass", "fail"}
                        or not isinstance(entry["fingerprint"], str)
                        or (entry["status"] == "pass" and not isinstance(entry["report"], str))
                    ):
                        raise ValueError("Invalid smoke ledger entry")
                if self.reserved > CAP_USD:
                    raise ValueError("Smoke ledger exceeds fixed cap")
            else:
                if (self.directory / "usage.json").exists() or (self.directory / "model_calls").exists():
                    raise ValueError("Smoke ledger missing but prior usage/cache exists; refusing to spend again")
                self.data = {"version": 1, "models": {}}
            return self
        except BaseException:
            os.close(self.lock_fd)
            self.lock_fd = None
            raise

    def __exit__(self, *args):
        os.close(self.lock_fd)

    @property
    def reserved(self):
        return sum(e["reserved_usd"] for e in self.data["models"].values())

    def save(self):
        tmp = self.path.with_suffix(".tmp")
        fd = os.open(tmp, os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump(self.data, f, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, self.path)
        # Commit the directory entry too before issuing a potentially billable call.
        directory_fd = os.open(self.directory, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)

    async def probe(self, model, fingerprint, call):
        existing = self.data["models"].get(model)
        if existing is not None:
            if existing["fingerprint"] != fingerprint:
                return False, "FAIL: changed input; this cache directory already reserved its one attempt", False
            if existing["status"] == "pass":
                return True, existing["report"], True
            return False, "FAIL: prior failed/interrupted attempt; no automatic retry (may have been billed)", True
        cost = RESERVATIONS[model]
        if self.reserved + cost > CAP_USD:
            return False, "FAIL: $0.10 reservation cap would be exceeded; no request sent", False
        entry = {"fingerprint": fingerprint, "reserved_usd": cost, "status": "started"}
        self.data["models"][model] = entry
        self.save()  # reserve before network; never release on timeout/cancellation
        try:
            report = await call()
        except Exception as exc:
            # Never print raw SDK errors: they may contain uploaded content.
            report = f"FAIL: {exc.code if isinstance(exc, AppError) else type(exc).__name__}; no retry"
            entry.update(status="fail", report=report)
            self.save()
            return False, report, False
        entry.update(status="pass", report=report)
        self.save()
        return True, report, False


def silence_wav():
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(b"\0\0" * 16000)
    return out.getvalue()


async def run(
    image_path: Path,
    api_key: str,
    cache_dir: Path,
    audio_path: Path | None = None,
    concept: str = "tear",
    http_client=None,
) -> int:
    if not api_key.strip():
        print("SKIP: META_API_KEY unset; no files read, no cache written, no requests sent.")
        return 0
    if concept not in {"tear", "hole", "open seam"}:
        raise ValueError("SAM concept must be one supported noun phrase")
    # Validate every input before reserving or sending any requests.
    if image_path.stat().st_size > 20_000_000:
        raise ValueError("Image exceeds the 20 MB smoke input limit")
    req = prepare_request(AnalyzeRequest(image_base64=base64.b64encode(image_path.read_bytes()).decode("ascii")))
    audio, duration = ensure_wav(audio_path.read_bytes() if audio_path else silence_wav())
    if duration > MAX_AUDIO_SECONDS:
        raise ValueError("Smoke audio must be at most 5 seconds")
    system = load_prompt("classify")
    text = "Protokolltest ohne Foto. Antworte category=unsupported, risk_level=warn_only, reason=Kein Foto."
    text_bytes = len(json.dumps([system, text, inline_schema(ClassifyResult)], ensure_ascii=False).encode())
    if text_bytes > 8192:
        raise ValueError("Spark smoke text/schema exceeds the 8 KiB bound; no requests sent")
    settings = Settings(
        meta_api_key=api_key.strip(),
        mock_mode=False,
        cache_model_calls=True,
        cache_dir=cache_dir,
        daily_budget_usd=CAP_USD,
        muse_max_completion_tokens=SPARK_OUTPUT_LIMIT,
    )  # fixed endpoint/model IDs; environment cannot redirect credentials or change prices
    with SmokeState(cache_dir) as state:
        client = RealMetaClient(settings, Budget(cache_dir / "usage.json", CAP_USD), http_client=http_client)
        try:

            async def spark():
                raw = await client._chat(system, text, [], "classify", ClassifyResult)
                result = parse_model_json(raw, ClassifyResult)
                if result.category != "unsupported" or result.risk_level != "warn_only":
                    raise ValueError("Protocol classification did not match the fixture")
                return "PASS: chat.completions + json_schema (text-only)"

            async def sam():
                segments = await client.segment(req, "textile", [concept])
                masks = sum(s.mask is not None for s in segments)
                return f"PASS: responses + SAM parser; {len(segments)} segments, {masks} polygons (zero-match is valid)"

            async def voice():
                transcript = await client.transcribe(audio, duration)
                if audio_path and not transcript:
                    raise ValueError("Speech sample returned an empty transcript")
                return f"PASS: multipart request+audio WAV; {len(transcript)} transcript characters"

            fingerprints = [
                ModelCache.key("spark-text-v1", system, text, inline_schema(ClassifyResult), SPARK_OUTPUT_LIMIT),
                ModelCache.key("sam-v2", req.image_base64, concept),
                ModelCache.key("voice-v1", hashlib.sha256(audio).hexdigest()),
            ]
            passed = True
            print(f"Cost guard: fixed ${CAP_USD:.2f} cap; worst-case reservations ${sum(RESERVATIONS.values()):.6f}.")
            for (model, call), fingerprint in zip(
                [
                    (settings.muse_model, spark),
                    (settings.sam_model, sam),
                    (settings.transcribe_model, voice),
                ],
                fingerprints,
                strict=False,
            ):
                ok, report, cached = await state.probe(model, fingerprint, call)
                passed = passed and ok
                print(f"{model}: {report} [{'CACHED; no request' if cached else 'at most one attempt'}]")
            print(f"Reserved including uncertain attempts: ${state.reserved:.6f} / ${CAP_USD:.2f}.")
            print(
                "UNBESTÄTIGT: Spark image input and Prompt B quality; SAM photo alignment/concept quality; final provider billing and max_completion_tokens enforcement."
            )
            if not audio_path:
                print(
                    "UNBESTÄTIGT: German ASR quality (in-memory silence checks the protocol only; use --audio for speech)."
                )
            print("OVERALL: " + ("PASS (protocol smoke only)" if passed else "FAIL (no automatic retries)"))
            return 0 if passed else 1
        finally:
            await client.aclose()


def main(argv=None):
    # Do not load .env: the user's exported key is the only switch that can spend credits.
    key = os.environ.get("META_API_KEY", "").strip()
    if not key:
        print("SKIP: META_API_KEY unset; no files read, no cache written, no requests sent.")
        return 0
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("image", type=Path)
    p.add_argument("--audio", type=Path, help="WAV speech sample, at most 5 seconds; default: 1 second silence")
    p.add_argument("--concept", choices=["tear", "hole", "open seam"], default="tear")
    p.add_argument("--cache-dir", type=Path, default=PROXY_DIR / ".cache/smoke_real")
    args = p.parse_args(argv)
    try:
        return asyncio.run(run(args.image, key, args.cache_dir, args.audio, args.concept))
    except (Exception, KeyboardInterrupt) as exc:
        print(f"OVERALL: FAIL ({type(exc).__name__}); no automatic retry. Keep the cache/ledger.")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
