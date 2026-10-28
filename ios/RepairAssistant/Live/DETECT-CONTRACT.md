# Live detection contract

The iOS client expects `POST {AppSettings.baseURL}/detect`. This endpoint is a
contract for the upcoming proxy implementation; the client does not change the
proxy. It is separate from `/analyze` and does not supply diagnosis or safety decisions.

Content-Type: `application/json` (request and response).

```json
{
  "image_base64": "<raw JPEG bytes, base64 encoded, no data URL prefix>",
  "concept": "tear"
}
```

The image is upright, without EXIF rotation, JPEG quality 0.8, with longest side at
most 768 pixels; aspect ratio is preserved and smaller images are not enlarged.
Concepts: Kleidung tries `tear`, then `hole` after an empty result, cycling on
continued misses. Schuh uses `detached sole`; Elektronik uses `wire`.

HTTP 200 response (existing `Segment` JSON shape):

```json
{
  "segments": [{
    "id": "damage_1",
    "label": "Riss",
    "kind": "damage",
    "prompt": "tear",
    "mask": {"points": [[0.33, 0.47], [0.47, 0.44], [0.66, 0.48], [0.62, 0.53], [0.34, 0.54]]},
    "box": [0.33, 0.44, 0.33, 0.10],
    "score": 0.94
  }]
}
```

`mask.points` is an implicitly closed polygon with at least three finite `[x,y]`
vertices in `[0,1]`, relative to the submitted image: origin top-left, x right,
y down. `box` is optional `[x,y,width,height]`, also normalized. Return an empty
`segments` array for no match. Return scores in `[0,1]`; the scan uses damage masks
scoring at least 0.5. Malformed/nonfinite/degenerate masks are ignored; boxes alone
do not qualify for automatic capture. IDs should be stable when practical, but
the client does not depend on stable IDs or polygon vertex counts.

Errors use non-200 HTTP status codes. The client displays the error, clears the
capture hold, and retries at its normal cadence (12-second request timeout).
Never return a guessed mask as success when the model failed. No images should be
persisted or logged by this endpoint.

The client permits one detection request in flight, with at least one second
between starts, including across category changes. The displayed latency measures
encoding plus HTTP round trip and decoding (the mock includes its ~700 ms delay).
Registration runs independently on the newest available frame. Input frames and
full-resolution captures are portrait/upright on a device; preview and geometry
share the same aspect-fill crop. Vision operates on at most 384-pixel images and
its bottom-left pixel transform is converted to normalized top-left coordinates.
The floating image is the detection/photo and the reference image is the current
frame; see [Apple's registration example](https://devstreaming-cdn.apple.com/videos/wwdc/2017/510lf4jlju5s1/510/510_advances_in_core_image_filters_metal_vision_and_more.pdf).

A valid mask must stay within movement/scale tolerances for 1.2 seconds before
`AVCapturePhotoOutput` captures a full-resolution photo. Tracking loss, stale
detection (>2.5 s), missing masks, interruptions, or frame gaps reset the hold.
Only successful photo delivery marks the state captured. The image goes through
`FlowModel.choose`, including the same review/analysis and safety gates as gallery
photos. Live detection never authorizes a repair.

Simulator and demo mode use `DemoImageFactory` pixels with slow synthetic pan/zoom
(steady with Reduce Motion), `MockLiveDetector`, real Vision registration and the
same hold/capture state machine. The HUD labels this mode Demo. The mock's fixture
mask is registered into the submitted frame; its default is a central tear polygon.
Live stitching reuses the planner output and existing `StitchPathView` renderer,
including darning phase, numbered points, thread and needle. Registration is planar;
lost registration hides the path and asks the user to aim at the marked area.

Physical-device validation still needs camera permission, autofocus, full-resolution
photo delivery, interruptions, registration accuracy and sustained frame-rate checks.
The preview targets 30 fps; registration drops old frames rather than queuing work.
