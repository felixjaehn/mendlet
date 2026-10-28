# Repair Assistant: fix it on your own photo

Take a photo of a torn shirt, a split seam or a sneaker whose sole is coming off. The app marks the damage pixel-accurately on **your** photo, tells you honestly whether to repair it yourself, go to a pro or replace it, builds a shopping list and then guides you step by step. For textiles it draws an animated stitch path along the real tear: where the needle goes in and where it comes out.

> Meta Global AI Developer Hackathon 2026 · Indie track · Theme: **Build for Your World**

**Why it matters:** Every second, one garbage truck of clothing is landfilled or burned worldwide (Ellen MacArthur Foundation). Every person in the EU throws away about 16 kg of textiles a year (EEA, 2022). Wearing clothes nine months longer cuts their footprint by up to 20 % (WRAP). Many of those items fail at one tear that could be fixed in 20 minutes. Sources and verification status: [`docs/impact.md`](docs/impact.md).

## Built during the hackathon

**Everything in this folder was created during the hackathon (first commit 2026-10-26, building period Oct 27 – Nov 4).** No code, assets or data from earlier projects are used. `git log -- repair-assistant` shows the full history.

| Area | What was built | Where |
| --- | --- | --- |
| Proxy | FastAPI backend with SSE progress, safety gate, SAM 3.1 stream parser, budget cap, call cache, benchmark runner | `proxy/app` |
| iOS app | SwiftUI app: capture, analysis, diagnosis with SAM overlays, decision, shopping list, guided repair, safety block screens | `ios/RepairAssistant` |
| Stitch path | Own geometry: mask → skeleton → centerline → evenly spaced stitches; darning grid for holes. No model computes coordinates | `ios/RepairAssistant/Rendering/StitchPathPlanner.swift` |
| Prompts | Versioned prompts for classification, diagnosis and step help | `prompts/` |
| Docs | PRD, API notes from primary docs, benchmark, demo script | `docs/` |

## How Meta's models are used

| Model | Job in the app | Why this model |
| --- | --- | --- |
| **SAM 3.1** (`sam-3.1`) | Finds the tear, hole, open seam or detached sole and returns pixel-accurate masks; the masks drive the overlays and the computed stitch path | Only SAM delivers geometry; the stitch path needs a real mask |
| **Muse Spark** (`muse-spark-1.3`) | Safety and category check before anything else; diagnosis, decision, shopping list and steps as schema-validated JSON; reads the care label (material changes needle, thread and stitch) | Image understanding + structured output |
| **Muse Voice Transcribe** (`muse-voice-transcribe-1.0`) | Describe the damage or answer follow-up questions by voice | Hands are busy while repairing |

Status of every live call and its measured quality: [`docs/STATUS.md`](docs/STATUS.md) and [`docs/benchmark.md`](docs/benchmark.md).

## Safety

The app only gives instructions where a mistake stays harmless. Lithium batteries (also in heated clothing), mains-powered devices, helmets and child seats are blocked **before** any diagnosis. Costs and times are labelled as estimates. Rules: `proxy/app/safety.py`, tests: `proxy/tests/test_safety.py`.

## Run it

```zsh
# Proxy (mock mode without a key, real mode with META_API_KEY in proxy/.env)
cd proxy && uv sync && uv run pytest -q
uv run uvicorn app.main:app --host 0.0.0.0 --port 8787

# iOS: open ios/RepairAssistant.xcodeproj, run scheme RepairAssistant.
# Settings → turn off demo mode and set the proxy URL to use the live pipeline.
```

The Meta Model API key stays on the proxy and is never shipped in the app or committed. Standard mode only (no Contributor models).

## Assets

All icons are SF Symbols. Test photos in `testdata/` are listed with their source in `testdata/SOURCES.md`; AI-generated images are labelled as such. Design references from Mobbin were used for inspiration only (`docs/design-notes.md`).
