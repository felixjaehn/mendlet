# Status

Last updated: 2026-10-29 (morning).

| Question | Answer |
| --- | --- |
| Textile demo runs live (real Meta API) | **yes**: 6 textile cases in the live benchmark |
| Shoe demo runs live | **yes**: 4 shoe cases |
| Electronics outlook runs live | **yes**: USB board, wires and pads with polarity, solder overlays |
| Safety blocks live | **yes**: 4 of 4 hazard cases blocked in 2–4 s; one over-cautious block (USB socket) |
| Muse Image after-repair preview live | **yes**: jeans and sweater, 11–12 s |
| Muse Wonder agent live | **yes** (opt-in `AGENT_MODE=wonder`): verifies masks, recovered from a SAM HTTP 500 |
| Muse Voice live | **yes**: error-free German transcript with keyword biasing, 2.9 s |
| Full benchmark | 16 cases: 16/16 category, 4/4 blocks, 10/11 overlays on damage, 0 invalid JSON, mean 23.7 s ([benchmark.md](benchmark.md)) |
| Tests | proxy 250 (offline), iOS 82 |
| Languages | German and English end to end (UI, model outputs, voice), real English demo recordings |
| API cost so far | about $2 of $150 (proxy budget: $0.75 on Oct 28, $1.22 on Oct 29; probes outside the proxy a few cents) |
| Independent judge score | 5.4 (Oct 28 baseline) → 6.3 → 6.5 (Oct 29) |

## Needs the human

- **Demo video** (3 min) from `docs/demo-script.md`, recorded on a real iPhone with the live proxy and real hands. This is the primary judging artifact.
- **Real-device run** of the live scan and "Live auf dem Stoff" (the simulator has no camera; both are verified only with the synthetic demo feed).
- **Real photos** of a real garment, shoe and USB board for 2–3 extra benchmark rows (current test photos are AI-generated and labelled).
- **Public repository** with remote and licence; confirm no secrets in history (`proxy/.env` is git-ignored).
- **Discord**: confirm that work after the Oct 26 kickoff counts and whether judges run the app.

## Known limitations

- Latency ~22–24 s (classic path), ~50 s in Wonder agent mode.
- SAM cannot find gaps (tears, open seams) by name; Spark grounding provides the box. Extra false positives remain on some photos (buttonholes, seams).
- Open-weight models (Glimmer, Spark Open) are not used.
