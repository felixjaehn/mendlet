# Repair assistant proxy

FastAPI service between the iOS app and the Meta Model API. It keeps the API key off the device, enforces a daily spend limit, validates every model answer against the JSON contract and applies the deterministic safety rules (blocked categories such as mains power, batteries and helmets never get repair instructions). Input images, video and audio are never stored or logged.

Pipeline per photo: classify (Muse Spark) -> segment (SAM 3.1 text prompts, Spark-guided grounding as fallback) -> diagnose and plan (Muse Spark). An optional agent mode (Muse Wonder tool loop) replaces the last two steps.

Without an API key the proxy runs in mock mode with deterministic fixtures, so the app and all tests work offline.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/health` | Mode, spend today, daily limit, agent mode |
| POST | `/analyze` | Photo to diagnosis, segments and repair guide. SSE (`progress`, `segments`, `grounding`, `agent_step`, then `result` or `error`); `?stream=false` returns plain JSON |
| POST | `/step-help` | Help for a single repair step |
| POST | `/step-image` | Preview image for a single step |
| POST | `/transcribe` | Multipart WAV `file` to `{"text": ...}` |
| POST | `/refine` | Tap points or box to one damage segment |
| POST | `/detect` | Live camera frame and one concept to segments |
| POST | `/track` | Base64 MP4 and one concept to frames with stable object IDs |
| POST | `/after-preview` | Photo and diagnosis to a repaired-state preview image |

Request and response details, SSE order and error codes: [API.md](API.md).

## Setup

```bash
cd proxy
uv sync
cp .env.example .env    # add META_API_KEY; leave empty for mock mode
```

Every variable is documented in `.env.example`; real environment variables win over `.env`.

## Run

```bash
uv run uvicorn app.main:app --port 8787
# reachable from a phone or simulator on the LAN:
uv run uvicorn app.main:app --host 0.0.0.0 --port 8787
```

```bash
curl -s localhost:8787/health
curl -s -X POST 'localhost:8787/analyze?stream=false' -H 'Content-Type: application/json' \
  -d '{"image_base64":"<base64>","mock_scenario":"battery_jacket","locale":"de"}'
```

Mock scenarios (request field `mock_scenario`, or keywords in `user_note`): `textile_tear_needs_label` (default), `textile_tear`, `textile_hole`, `textile_open_seam`, `textile_button`, `textile_grounding`, `textile_multi`, `textile_rings`, `shoe_sole`, `battery_jacket`, `helmet`, `unsupported`.

## Tests

```bash
uv run pytest -q    # fully offline, real HTTP transports are blocked
uv run ruff check . && uv run ruff format --check .
```

The suite checks the requests the SDK actually serialises (against `httpx.MockTransport`), SSE parsing, multipart audio, caching, the safety rules and the complete pipeline. SAM wire fixtures in `tests/fixtures/sam/` are synthetic; regenerate them with `uv run python scripts/build_sam_fixtures.py`.

## Benchmark

```bash
uv run python scripts/run_benchmark.py --fast              # mock mode, markdown table
uv run python scripts/run_benchmark.py --dump out/         # keep raw responses
uv run python scripts/overlay_contact_sheet.py out/ sheet.jpg
```

Uses `../testdata/cases.json`. Results and findings: [../docs/benchmark.md](../docs/benchmark.md).

## Live checks

`scripts/smoke_real.py` is a budget-capped (0.10 USD) one-attempt-per-model smoke test. It needs an exported `META_API_KEY` (it deliberately ignores `.env`) and exits with `SKIP` otherwise:

```bash
export META_API_KEY=...
uv run python scripts/smoke_real.py /path/to/photo.jpg [--audio sample.wav] [--concept hole]
```

`scripts/probe_live.py` is an exploratory Spark and SAM probe for manual use. Real calls are cached under `.cache/` when `CACHE_MODEL_CALLS=1`.

## Design notes

- Blocked answers carry empty `segments`, `shopping_list` and `guide.steps`; `diagnosis` and `decision` hold placeholders so the app never decodes `null`.
- The keyword pre-check on `user_note` can only make the risk stricter, never looser. It does not understand negation ("without battery" is still blocked); this is deliberate.
- If classification is still invalid after one retry, the result is `warn_only`.
- The daily budget is tallied after successful responses and can be exceeded by parallel calls; it is not a hard reservation.
- Prompts are versioned files in `../prompts`, see its README.
