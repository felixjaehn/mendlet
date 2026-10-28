# Judging Brief: Meta Global AI Developer Hackathon 2026

Input for an independent judge agent. Primary source: the official **Participant Guide** on Cerebral Valley (`cerebralvalley.ai/e/meta-ai-developer-hackathon/details`, read 2026-10-28 while logged in) and the Meta model list (`dev.meta.ai/docs/models`, read 2026-10-28).

## Problem statements (project must fit one)

- **Build for Your World**: Bring Meta's models into your domain. Solve a problem you know firsthand, free up time and mental space, and make something possible that wasn't before. ← this project
- **Push the Frontier**: software, robotics, manufacturing, energy, materials; give a machine a new capability, understand/control a physical system.

The project must incorporate Meta's models: Muse Spark series, Muse Wonder, Muse Image, Muse Voice Transcribe and SAM 3.1 via Meta Model API; open weights Muse Glimmer and Muse Spark Open; Muse Code coding agent.

## Rules

- **Repositories must be public.**
- Max team size 4; solo allowed. This project: solo, **Indie Developer track**.
- **Demo must only highlight features, code and functionality built during the Hackathon** (building period Oct 27 – Nov 4). Judges must be able to clearly identify what was created during the Hackathon; failing that → immediate disqualification.
- New work only, clearly marked in the submission.
- Disqualified: violating legal, ethical or platform policies; using code, data or assets without rights.
- **Anti-projects (avoid)**: AI medical advice, basic RAG apps, **Simple Image Analyzers**, simple AI-for-education chatbots, job application screeners, nutrition coaches, personality analyzers, sports coaches, anything political or war-related.

## Submission

- Via the CV platform by **Nov 4, 9:00 PM ET**. Public repo, accessible video link, all contributors listed.
- **Three-minute demo video** highlighting what was built during the Hackathon. The video is one of the primary artifacts judges use, **along with the code and the live product**.

## Judging

- **Stage 1 (pass/fail)**: fits a theme and reasonably used Meta Model API and/or Meta's open-weight models, built in the Hackathon.
- **Stage 2**: each category scored 0–10:

| Category | Weight | Official question |
| --- | --- | --- |
| Impact | 30 % | What's the real-world potential here? Who benefits, and how much does it matter? Could this actually become something people use? Does it fit into one of the problem statements? |
| Use of Meta AI Tooling | 25 % | How creatively did this team use Meta's AI tooling? Did they go beyond a basic integration? Did they surface capabilities that surprised even us? |
| Technical Depth & Execution | 20 % | Is the engineering sound and thoughtfully refined? Does this feel like something that was thought through with real craft? |
| Demo | 25 % | Is this a working, impressive demo? Does the product hold up live? Is the demo video genuinely cool to watch? |

- **Stage 3**: top 5 per track; final judges watch the video demos live and rank them with the same rubric.
- Indie track lens (event page): creativity, technical ambition, whether it works.

## Prizes relevant to this project

Indie track: 1st $150K, 2nd $100K, 3rd $75K, 4th $50K, 5th $25K. Bonus: Most Viral Project on X ($20K), Best Build on Meta Open Weight Models (Glimmer / Spark Open, $10K), Community Vote ($10K), Best Agentic Use-Case ($5K, autonomy and multi-step workflows), Best Creative Build ($5K, Muse Image or Muse Wonder).

## Meta models available (dev.meta.ai/docs/models)

- `muse-spark-1.3`: text/image/video/audio/PDF → text; tool calling, structured output, search grounding, perception grounding (0–1000 coordinates).
- `muse-wonder-1.0` (preview): Meta's most capable model for long-horizon agentic work, plans, delegates to sub-agents, calls tools in parallel, recovers from errors.
- `muse-image-1.0`: image generation **and editing** (text + optional reference images → image), agentic; `/v1/images/generations`, `/v1/images/edits`, or Responses for multi-turn editing.
- `muse-voice-transcribe-1.0`: speech-to-text, realtime WebSocket (`wss://api.meta.ai/v1/asr/realtime`) or file endpoint; endpointing, keyword biasing, 25 languages.
- `sam-3.1`: text prompt, image or video → boxes and pixel-accurate masks; box/point prompts; in video it follows each object across frames.
- Open weights: Muse Spark Open (816B MoE), Muse Glimmer (on-device capable, e.g. ExecuTorch).

## How to judge

1. Read `repair-assistant/docs/PRD.md`, `docs/STATUS.md` (if present), `docs/demo-script.md`, `docs/benchmark.md`, `docs/impact.md`, the README, and look at the screenshots in `docs/screenshots/`.
2. Inspect the code (`proxy/app`, `ios/RepairAssistant`) to verify claims. Do not trust docs that the code does not back.
3. Check Stage 1 and every rule above (public repo readiness, build-phase marking, asset rights, anti-project risk).
4. Score each category 0–10 with justification and compute the weighted total (0–10).
5. For every category below 10, list concrete, actionable gaps, ordered by expected score gain per hour of work. Be strict: a 10 means a clear winner among thousands of entries.
