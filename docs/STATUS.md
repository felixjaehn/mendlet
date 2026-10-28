# Status

Last updated: 2026-10-28 (evening).

| Question | Answer |
| --- | --- |
| Textile demo runs (demo mode) | yes |
| Textile demo runs live (real Meta API) | not yet tested |
| Shoe demo runs | demo mode only |
| Real Meta API calls so far | none (key is in place since 2026-10-28) |
| API cost so far | $0.00 |
| Benchmark | pending (test photos being generated) |
| Independent judge score (docs/JUDGING-BRIEF.md) | 5.4 / 10 (2026-10-28, baseline) |

## In progress

- Test photos (AI-generated, labelled) for textile, shoes, labels, safety and electronics.
- Proxy: SAM box/point prompts (`/refine`), video tracking (`/track`), Spark grounding fallback, multi-instance masks, Muse Image after-repair preview.
- iOS: mask overlays with scan reveal and label pins; live camera damage detection with on-device tracking and a live stitch path.

## Next

1. Smoke test, then first real end-to-end run on photos; record results in `docs/benchmark.md`.
2. Muse Wonder as a self-verifying repair agent; Voice Transcribe hands-free control.
3. Shoe and electronics overlays; benchmark; demo video.
