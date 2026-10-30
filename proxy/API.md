# API contract extensions

All original required fields and SSE events are unchanged. The additional fields below must be decoded as optional on iOS. Live behaviour of all newer model paths is **UNCONFIRMED**; tests run offline only. Error messages and user-facing texts are localised (`locale: "de" | "en"`), the field names and codes are not.

## Shared response fields

### Segment

In addition to `id`, `label`, `kind`, `prompt`, `box`, `mask`, `score`:

```typescript
source?: "text" | "tap" | "grounding" | null
```

`text`: SAM concept search (also used for tracking). `tap`: manual points/box. `grounding`: Spark box plus an actually returned SAM mask. Older responses without `source` stay valid. Segment IDs are unique within one analysis, not globally. Several instances of the same concept each get an ID; overlapping boxes of the same concept are kept, and there is no cap of eight segments. Overlapping synonyms (`tear`/`rip`) are still merged.

### Mask

`mask` stays nullable, `format` stays `"polygon"`, `points` stays the largest outer ring. Additionally:

```typescript
rings?: Array<{
  points: Array<[number, number]>;
  hole: boolean;
}> | null
```

All coordinates are normalised (0..1) relative to the whole oriented photo, not to the segment box. `hole: false` is an outer ring or island; `hole: true` is an inner hole to cut out. Rings are closed polygons without a repeated end point. For SAM rasters they are ordered by descending area; `rings[0].points` equals `points`. Draw all rings together with the even-odd fill rule (islands inside holes included) rather than painting every hole last. Old clients can keep drawing only `points`. Broken masks fall back to `mask: null` and the valid box, as before.

## POST /analyze

Request unchanged. The JSON result and the SSE `result` additionally contain:

```json
{"instances": {"tear": 2, "hole": 1}}
```

Type: `instances?: Record<string, number> | null`. Key = `prompt` of the returned damage segments (`kind: "damage"`), value = non-negative count. Parts are not counted. Concepts without returned damage are absent; a finished analysis without damage segments returns `{}`, early-blocked cases currently return `null`. Counted after synonym merging; do not read it as the true number of damages.

If the SAM text search succeeds but finds no damage, Spark grounding follows, then SAM with a box. Spark returns `[x1,y1,x2,y2]` on a 0-1000 grid; values outside are clamped to the image, empty or inverted boxes are rejected. With no visible damage (`box: null`) or no SAM mask, no damage is invented. Existing part segments are kept. Budget errors are propagated; other grounding errors fall back to the text-only diagnosis.

Optional SSE event right before the fallback:

```text
event: grounding
data: {"label":"Locating the damage more precisely"}
```

Order in a successful fallback: `progress(classify)`, `progress(segment)`, `grounding`, `progress(diagnose)`, `progress(plan)`, `result`. Without fallback nothing changes. `grounding` is not a new value of the existing `stage` enum. `error` is unchanged.

### SSE event `segments`

`event: segments`, `data: {"segments": [Segment, ...]}` directly after segmentation (and the optional `grounding`), before `progress(diagnose)`. The segments (JSON and IDs) are identical to `result.segments`, so the app can draw masks while the diagnosis is still running. Order: `progress(classify)`, `progress(segment)`, [`grounding`], `segments`, `progress(diagnose)`, `progress(plan)`, `result`. Blocked cases do not send `segments`. Older clients ignore unknown events.

### Weak-segment filter

Damage segments with a score below 0.6 are dropped when their box overlaps a stronger damage segment (IoU > 0.3 or more than 60 % of the weak box lies inside). Part segments with a score below 0.6 are dropped, and at most three parts (the best) are kept. IDs are reassigned afterwards as `seg_1`, ... and `instances` counts the remaining damage segments. Basis: live cases pullover (`rip` x2 at 0.52 against three `hole`) and sneaker (four weak `seam`), see `docs/benchmark.md`.

### `decision.second_life`

Only for `recommendation: "replace"`: up to three ideas for the old item, `[{kind: "upcycle"|"recycle"|"donate", title, text}]`. For all other recommendations and for blocked cases the proxy enforces `[]`. Older clients ignore the field.

## POST /refine

```json
{
  "image_base64": "<base64 or image data URL>",
  "points": [
    {"x": 0.5, "y": 0.5, "label": "positive"},
    {"x": 0.6, "y": 0.5, "label": "negative"}
  ],
  "box": [0.25, 0.25, 0.5, 0.5],
  "label": "tear"
}
```

`image_base64`: string, at most 25,000,000 characters. `points`: optional, default `[]`, at most 256. `x`/`y`: finite numbers in 0..1; the point `label` is exactly `positive` or `negative`. `box`: optional/null, `[x,y,w,h]` in 0..1, positive area, fully inside the image. At least one box or one positive point is required. Top-level `label`: non-empty string, at most 200 characters.

Coordinates refer to the whole photo **after EXIF orientation**, without UI margins or crops. The proxy orients/downscales to at most 1536 px and converts to the PNG size actually sent. Points are floored and clamped to valid pixels; the right/bottom box edge is ceiled and converted to inclusive x2/y2 for SAM. Example for a 640x480 image: `<0f>1<|box;x1=160;y1=120;x2=479;y2=359;w=640;h=480|><|point;x=320;y=240;w=640;h=480|>-<|point;x=384;y=240;w=640;h=480|>`. Positive points are concatenated directly; commas separate objects, not points. `label` is not sent to SAM as an extra text phrase. Metadata: `mask_encoding: "one_bit"`.

Response HTTP 200: **a single segment**, no envelope or array. `id: "seg_1"`, `source: "tap"`, `kind: "damage"`, `label` and `prompt` = request label; the rest of the segment contract is unchanged. The ID is valid for this single refinement response only. No match returns HTTP 422 with `error.code: "no_segment"`.

## POST /track

```json
{"video_base64":"<MP4 base64>","concept":"tear"}
```

`video_base64`: string, also `data:video/mp4;base64,...`; at most 50,000,000 decoded bytes (field limit 66,666,700 characters). The proxy checks base64 and the ISO-BMFF header, not codecs. `concept`: non-empty string, at most 200 characters; send exactly one short noun phrase.

```typescript
{
  frames: Array<{
    index: number;
    segments: Array<Segment & { object_id: string }>;
  }>;
  fps?: number | null;
}
```

The frame index is the original zero-based source frame (0..14999), frames ascending. `object_id` is the decimal ID returned by SAM as a **string**, not necessarily consecutive. `id` is `seg_<object_id>` and stays stable across frames regardless of score or order. Boxes/masks are normalised per frame. Explicitly empty frames have `segments: []`; missing frames are not invented. Completely empty SAM output yields `frames: []`. The HTTP endpoint returns JSON once the upstream SSE has completed (`response.completed`); an incomplete stream is an error and is not cached.

In real mode `fps` is currently omitted because no reliable frame rate is available; other null fields are omitted in `/track` as well. Mock: ten deterministic moving frames, `object_id: "7"`, `fps: 10`. Local video cost: $0.20 per 1000 frames, minimum 50, estimated from the highest returned frame index + 1. Missing trailing frames and live billing are **UNCONFIRMED**.

## POST /after-preview

```json
{
  "image_base64": "<base64 or image data URL>",
  "diagnosis_summary": "Tear along the side seam",
  "stitch_type": "ladder_stitch",
  "category": "textile",
  "repair_hint": "optional detail"
}
```

`image_base64`: as for `/refine`. `diagnosis_summary`: non-empty string, at most 2000 characters; use `diagnosis.summary` of the analysis. `stitch_type` (optional): exactly `ladder_stitch`, `running_stitch`, `darning` or `whip_stitch` (as in the overlay contract). `category` (optional): `textile` (default) or `shoe`; for `shoe` the prompt describes a cleanly re-glued sole without stitches or visible glue. `repair_hint` (optional): string, at most 200 characters, appended as a detail.

```json
{"image_base64":"<plain base64 image, no data URL>","model":"muse-image-1.0"}
```

Detect the image type from the decoded bytes; the model path may return PNG/JPEG/WebP. Muse Image receives an oriented PNG, a short English edit instruction built from diagnosis and stitch type, `n=1` and `response_format=b64_json` via multipart `POST /v1/images/edits`. The model must keep photo, material, perspective, lighting and background. The model name follows the server setting `IMAGE_MODEL` (default `muse-image-1.0`).

Successful HTTP responses are booked locally at $0.01 per image, even if the returned image content is invalid. With `CACHE_MODEL_CALLS=1` validated images are cached by model, prompt and image content; cache hits are not booked again. Fallback URLs are not downloaded. Mock returns the oriented/downscaled photo as PNG with a tiny deterministic pixel change and uses no budget. Image quality and live price are **UNCONFIRMED**.

## POST /detect

Matches `ios/RepairAssistant/Live/DETECT-CONTRACT.md`. Request `{"image_base64": "...", "concept": "tear"}` (`concept` non-empty, at most 200 characters). Response `{"segments": [Segment, ...]}`, empty when nothing matches. The proxy downscales to at most 768 px and sends exactly one SAM text prompt (cached like any SAM call). With zero matches Spark does **not** localise (too slow for a live frame); the answer is `[]`. Damage concepts (`tear`, `rip`, `hole`, `open seam`, `frayed edge`, `detached sole`, `wire`) return `kind: "damage"`, IDs `damage_1`, `damage_2`, ... (parts `part_<n>`), `source: "text"`. The weak-segment filter applies here too. Errors as for the other endpoints. Mock: deterministic polygon per concept (tear, hole, sole, wire), score 0.94, about 0.5 s.

## Agent mode (`AGENT_MODE=wonder`, off by default)

After the deterministic safety/classification stage (never inside the agent; blocked cases never start it) a Muse Wonder tool loop on the Responses API replaces the segmentation and diagnosis steps. Tools: `segment(concept)`, `segment_at(box_0_1000, points?, concept?)`, `locate(description)`, `verify_mask(segment_id)`, `finish(...)` (plan shaped like `DiagnosePlan`). At most 8 rounds. An invalid `finish`, the round limit, an answer without tool call or an upstream error falls back to the normal diagnosis call or the classic pipeline (budget errors do not).

New SSE event per executed tool:

```text
event: agent_step
data: {"n": 1, "tool": "segment", "label": "SAM searches for rip", "model": "sam-3.1", "status": "done", "ms": 5200}
```

`model`: `sam-3.1`, `muse-spark-1.3` (locate, verify_mask) or `muse-wonder-1.0` (finish); `status`: `done` or `failed`; `n` counts in call order, parallel calls emit in completion order. Flow: `progress(classify)`, `progress(segment)`, `agent_step`*, `segments`, `progress(diagnose)`, `progress(plan)`, `result`. `segments` arrives once after the agent run; it contains only kept segments (damage masks rejected by `verify_mask` are dropped), IDs are stable within the run and match the result. `source`: `text` (segment), `grounding` (segment_at with box), `tap` (segment_at with points only). The mock agent plays six steps (segment x2, locate, segment_at, verify_mask, finish) with delays. `/health` additionally reports `agent_mode`.

Wonder pricing (standard mode, https://dev.meta.ai/docs/pricing-rate-limits, read 2026-10-28): $4.00 input, $20.00 output, $0.20 cached input per 1M tokens. Actual billing, reasoning tokens in usage and live behaviour of the tool loop are **UNCONFIRMED**.

## Errors

Existing AppError envelope: `{"error":{"code":"...","message":"..."}}`. Image/video decoding errors are HTTP 422 (`invalid_image`/`invalid_video`), oversized decoded videos 413, the daily limit 429 (`budget_exceeded`), model errors 502 (`model_output_invalid`/`upstream_error`), timeouts 504 (`timeout`). Pydantic request validation still returns FastAPI's 422 with `detail`. The endpoints check the existing daily budget before the model call; it remains an after-the-fact cost tally and can be exceeded by parallel calls.
