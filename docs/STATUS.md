# Status

Last updated: 2026-10-29 (night).

| Question | Answer |
| --- | --- |
| Textile demo runs live (real Meta API) | **yes**: jeans tear, sweater with 3 holes (`docs/benchmark.md`) |
| Shoe demo runs live | **yes**: sneaker with detached sole |
| Safety block live | **yes**: heated jacket with lithium battery blocked in 3 s |
| Muse Image after-repair preview live | **yes**: jeans and sweater, 11–12 s |
| Electronics outlook | SAM finds red/black wire and bare ends live; solder overlay in progress |
| Latency photo → plan | 29.9 s live (target < 30 s), down from 46.5 s |
| API cost so far | about $0.55 of $150 |
| Independent judge score | 5.4 / 10 (2026-10-28 baseline, before any live run) |

## Key live finding

SAM 3.1 finds objects but not a tear by name ("tear" = 0 matches on an obvious tear). Muse Spark locates the damage on its 0–1000 grounding grid, SAM segments that box: pixel-accurate mask, score 0.94. This chaining is now the main path for damage (`proxy/app/pipeline.py`).

## In progress

- Proxy: `/detect` for the live camera, early `segments` SSE event, weak-segment filter, Muse Wonder agent mode with `agent_step` trace.
- iOS: demo mode replays real recorded model responses and photos; agent trace; Muse Image before/after slider; shoe glue overlay.

## Done since baseline

Live pipeline verified; prompt B v3 (label only when needed, safety confirmations only for cutting, heat, glue); latency tuning; mask overlays with scan reveal and label pins; live scan module (simulator demo feed); `/refine`, `/track`, `/after-preview`; real test photos (AI-generated, labelled).
