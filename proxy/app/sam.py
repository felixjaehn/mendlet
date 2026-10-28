"""SAM 3.1 helpers: prompts, output-text parsing, mask -> polygon conversion, de-duplication.

SAM answers with special-token text (see docs/api-notes.md section 2), one concept per request.
App-facing mask format is a polygon in normalized image coordinates:
    {"format": "polygon", "points": [[x, y], ...]}
"""

import math
import re
from dataclasses import dataclass

import numpy as np

from .models import Mask, MaskRing, RefinePoint, Segment, TrackFrame, TrackedSegment

# Short English noun phrases (SAM handles one concept per request).
SEGMENT_PROMPTS: dict[str, list[str]] = {
    # "tear" found nothing on a clear tear live (docs/benchmark.md); "rip" did, grounding covers the rest.
    "textile": ["rip", "hole", "open seam", "frayed edge", "garment", "button"],
    "shoe": ["shoe sole", "seam", "detached sole", "heel"],
    "low_voltage_electronics": ["cable", "connector", "housing"],
}

# prompt -> (German label, kind)
PROMPT_META: dict[str, tuple[str, str]] = {
    "tear": ("Riss", "damage"),
    "rip": ("Riss", "damage"),
    "hole": ("Loch", "damage"),
    "open seam": ("Offene Naht", "damage"),
    "frayed edge": ("Ausgefranster Rand", "damage"),
    "garment": ("Kleidungsstück", "part"),
    "button": ("Knopf", "part"),
    "fabric": ("Stoff", "part"),
    "shoe sole": ("Sohle", "part"),
    "seam": ("Naht", "part"),
    "detached sole": ("Abgelöste Sohle", "damage"),
    "heel": ("Absatz", "part"),
    "wire": ("Kabelschaden", "damage"),
    "cable": ("Kabel", "part"),
    "connector": ("Stecker", "part"),
    "housing": ("Gehäuse", "part"),
}

# Concepts the live camera (/detect) searches for; they are damage even when SAM_PROMPTS call them parts.
DETECT_DAMAGE_CONCEPTS = {"tear", "rip", "hole", "open seam", "frayed edge", "detached sole", "wire"}

MIN_SCORE = 0.25
DEDUP_IOU = 0.6


@dataclass
class SamDetection:
    prompt: str
    score: float
    box: tuple[float, float, float, float]  # x1, y1, x2, y2 normalized
    polygon: list[list[float]] | None = None  # normalized
    rings: list[MaskRing] | None = None
    object_id: str | None = None


def geometric_prompt(width: int, height: int, points: list[RefinePoint], box: list[float] | None = None) -> str:
    """One object; adjacent positive tokens, '-' negatives, commas only between objects."""
    from meta_sam_parser import FramePrompt, PromptBox, PromptObject, PromptPoint, build_object_prompt

    bounds = None
    if box is not None:
        x, y, w, h = box
        left, top = min(width - 1, int(x * width)), min(height - 1, int(y * height))
        bounds = PromptBox(left, top, min(width, max(left + 1, math.ceil((x + w) * width))),
                           min(height, max(top + 1, math.ceil((y + h) * height))))
    pixels = [PromptPoint(min(width - 1, int(p.x * width)), min(height - 1, int(p.y * height)), p.label)
              for p in points]
    return build_object_prompt(size=(width, height), objects=[PromptObject(1, [FramePrompt(box=bounds, points=pixels)])])


# ---- bitmap -> polygon --------------------------------------------------------

_DIRS = [(-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1)]  # (dy, dx), clockwise from N


def trace_contour(mask: np.ndarray) -> list[tuple[int, int]]:
    """Moore-neighbour outer contour of the first blob in raster order. Returns (y, x) pixels."""
    pad = np.pad(mask.astype(bool), 1)
    ys, xs = np.nonzero(pad)
    if len(ys) == 0:
        return []
    start = (int(ys[0]), int(xs[0]))
    p, b_dir = start, 6  # backtrack = west of start (background by construction)
    contour = [start]
    for _ in range(4 * len(ys) + 8):
        for i in range(1, 9):
            d = (b_dir + i) % 8
            ny, nx = p[0] + _DIRS[d][0], p[1] + _DIRS[d][1]
            if pad[ny, nx]:
                pd = (b_dir + i - 1) % 8
                back = (p[0] + _DIRS[pd][0], p[1] + _DIRS[pd][1])
                p = (ny, nx)
                b_dir = _DIRS.index((back[0] - p[0], back[1] - p[1]))
                break
        else:
            break  # isolated pixel
        if (p, b_dir) == (start, 6):
            break
        contour.append(p)
    return [(y - 1, x - 1) for y, x in contour]


def _simplify(points: list[tuple[float, float]], tol: float) -> list[tuple[float, float]]:
    """Douglas-Peucker on an open polyline (iterative)."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        (ax, ay), (bx, by) = points[a], points[b]
        dx, dy = bx - ax, by - ay
        norm = (dx * dx + dy * dy) ** 0.5 or 1.0
        best, idx = 0.0, -1
        for i in range(a + 1, b):
            px, py = points[i]
            dist = abs(dy * (px - ax) - dx * (py - ay)) / norm
            if dist > best:
                best, idx = dist, i
        if best > tol and idx != -1:
            keep[idx] = True
            stack += [(a, idx), (idx, b)]
    return [p for p, k in zip(points, keep) if k]


def _simplify_closed(pts: list[tuple[float, float]], tol: float) -> list[tuple[float, float]]:
    """Simplify a closed ring by splitting it at the point farthest from the first one."""
    x0, y0 = pts[0]
    j = max(range(len(pts)), key=lambda i: (pts[i][0] - x0) ** 2 + (pts[i][1] - y0) ** 2)
    first = _simplify(pts[: j + 1], tol)
    second = _simplify(pts[j:] + [pts[0]], tol)
    return first[:-1] + second[:-1]


def bitmap_to_rings(raster: np.ndarray, max_points: int = 80) -> list[MaskRing]:
    """All pixel-edge contours, largest first; winding distinguishes holes from islands."""
    mask = np.asarray(raster, dtype=bool)
    h, w = mask.shape
    if not h or not w or not mask.any():
        return []
    pad = np.pad(mask, 1)
    edges: dict[tuple[int, int], list[tuple[int, int]]] = {}

    def add(boundary, dx1, dy1, dx2, dy2):
        ys, xs = np.nonzero(boundary)
        for y, x in zip(ys.tolist(), xs.tolist()):
            edges.setdefault((x + dx1, y + dy1), []).append((x + dx2, y + dy2))

    add(mask & ~pad[:-2, 1:-1], 0, 0, 1, 0)
    add(mask & ~pad[1:-1, 2:], 1, 0, 1, 1)
    add(mask & ~pad[2:, 1:-1], 1, 1, 0, 1)
    add(mask & ~pad[1:-1, :-2], 0, 1, 0, 0)
    rings = []
    while edges:
        start = next(iter(edges))
        point, previous = start, (start[0] - 1, start[1])
        ring = []
        while point in edges:
            ring.append(point)
            options = edges[point]
            dx, dy = point[0] - previous[0], point[1] - previous[1]
            # Follow diagonal contacts too: thin tears can be 8-connected.
            target = (point[0] + dy, point[1] - dx)
            nxt = target if target in options else options[0]
            options.remove(nxt)
            if not options:
                del edges[point]
            previous, point = point, nxt
            if point == start:
                break
        if point == start and len(ring) >= 4:
            rings.append(ring)
    if not rings:
        return []

    def area(ring):
        return sum(x * yy - xx * y for (x, y), (xx, yy) in zip(ring, ring[1:] + ring[:1]))

    result = []
    for pts in sorted(rings, key=lambda r: abs(area(r)), reverse=True):
        tol = 0.2
        simp = _simplify_closed(pts, tol)
        while len(simp) > max_points:
            tol *= 1.5
            simp = _simplify_closed(pts, tol)
        if len(simp) >= 3 and area(simp):
            result.append(MaskRing(points=[[round(x / w, 6), round(y / h, 6)] for x, y in simp],
                                   hole=area(pts) < 0))
    return result


def bitmap_to_polygon(raster: np.ndarray, max_points: int = 80) -> list[list[float]]:
    """Keep the legacy largest exterior ring unchanged, without downsampling."""
    return next((r.points for r in bitmap_to_rings(raster, max_points) if not r.hole), [])


# ---- SAM output text -> detections -------------------------------------------

# Parse each record independently: a corrupt mask must not discard other matches
# or valid boxes in the same frame. Base85 excludes commas/semicolons/angle bars.
_RECORD_RE = re.compile(r"(?:^|,)(\d+)(<\|box;[^<>|]*\|>)(<\|mask;[^<>|]*\|>)?(?=,|$)")


def _box_fields(token: str, img_w: int, img_h: int):
    try:
        pairs = [field.split("=", 1) for field in token[6:-2].split(";")]
        fields = dict(pairs)
        if len(fields) != len(pairs):
            return None
        x1, y1, x2, y2, w, h = (int(fields[k]) for k in ("x1", "y1", "x2", "y2", "w", "h"))
        score = float(fields.get("c", "0.5"))
        if not math.isfinite(score) or not 0 <= score <= 1:
            return None
        if (w, h) != (img_w, img_h) or not (0 <= x1 <= x2 < w and 0 <= y1 <= y2 < h):
            return None
        return score, (x1 / w, y1 / h, (x2 + 1) / w, (y2 + 1) / h)
    except (ValueError, KeyError, TypeError):
        return None


def parse_sam_output(text: str, prompt: str, img_w: int, img_h: int, *,
                     frame_index: int = 0, video: bool = False) -> list[SamDetection]:
    """Documented key=value wire records -> validated boxes and polygons.

    The official library confirms box-local half-open mask bounds offline. Actual
    non-stream response envelopes and placement on real photos are UNBESTÄTIGT.
    Invalid masks degrade to boxes; invalid coordinates/frames are discarded.
    """
    if img_w <= 0 or img_h <= 0:
        return []
    try:
        from meta_sam_parser import CompletedOutcome, decode_mask_to_raster, image_segmentation_format, video_segmentation_format
    except ImportError:
        image_segmentation_format = None
    dets = []
    for line in text.splitlines():
        header = f"<{frame_index}f>"
        if not line.startswith(header):
            continue
        for match in _RECORD_RE.finditer(line[len(header):].strip()):
            oid, box_token, mask_token = match.groups()
            parsed = _box_fields(box_token, img_w, img_h)
            if parsed is None:
                continue
            score, box = parsed
            det = SamDetection(prompt, score, box, object_id=oid)
            dets.append(det)
            if mask_token is None or image_segmentation_format is None:
                continue
            # Bound allocations before the library decodes a claimed raster size.
            dims = re.search(r";data=(\d+),(\d+),[!~]", mask_token)
            if not dims or not (0 < int(dims[1]) * int(dims[2]) <= min(img_w * img_h, 4_000_000)):
                continue
            try:
                parser = (video_segmentation_format() if video else image_segmentation_format()).create_parser()
                parser.push(f"{header}{oid}{box_token}{mask_token}\n")
                records = parser.finish(CompletedOutcome()).result.records
                mrec = next((r for r in records if r.kind == "mask"), None)
                if mrec is None:
                    continue
                raster = np.frombuffer(decode_mask_to_raster(mrec.mask), dtype=np.uint8)
                raster = raster.reshape(mrec.mask.height, mrec.mask.width)
                b = mrec.bounds
                det.rings = [MaskRing(hole=ring.hole, points=[
                    [round((b.left + u * (b.right - b.left)) / img_w, 6),
                     round((b.top + v * (b.bottom - b.top)) / img_h, 6)] for u, v in ring.points
                ]) for ring in bitmap_to_rings(raster)] or None
                det.polygon = next((r.points for r in det.rings or [] if not r.hole), None)
            except (ValueError, ArithmeticError):
                # InvalidSegmentationMaskError is normally retained as a parser
                # diagnostic. No raw payloads are logged or exposed to the app.
                continue
    return dets


def parse_sam_video(text: str, prompt: str) -> list[TrackFrame]:
    """Parse source-frame records with the official video parser and stable SAM object IDs."""
    frames: dict[int, dict[str, TrackedSegment]] = {}
    for line in text.splitlines():
        header = re.match(r"^<(\d+)f>", line)
        if not header or not 0 <= int(header[1]) < 15_000:
            continue
        index = int(header[1])
        body = line[header.end():].strip()
        if not body:
            frames.setdefault(index, {})
        for match in _RECORD_RE.finditer(body):
            size = re.search(r";w=(\d+);h=(\d+)(?:;|\|>)", match[2])
            if not size or int(size[1]) <= 0 or int(size[2]) <= 0:
                continue
            raw = f"<{index}f>{match[1]}{match[2]}{match[3] or ''}"
            for det in parse_sam_output(raw, prompt, int(size[1]), int(size[2]), frame_index=index, video=True):
                records = frames.setdefault(index, {})
                for seg in detections_to_segments([det]):
                    records[det.object_id] = TrackedSegment(
                        **{**seg.model_dump(), "id": f"seg_{det.object_id}"}, object_id=det.object_id)
    return [TrackFrame(index=i, segments=list(records.values())) for i, records in sorted(frames.items())]


# ---- detections -> segments --------------------------------------------------


def _iou(a: tuple[float, ...], b: tuple[float, ...]) -> float:
    ix = max(0.0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0.0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / union if union > 0 else 0.0


def detections_to_segments(dets: list[SamDetection]) -> list[Segment]:
    """Merge detections of all prompts, drop low scores and overlapping duplicates, assign ids."""
    kept: list[SamDetection] = []
    for d in sorted(dets, key=lambda d: d.score, reverse=True):
        if d.score < MIN_SCORE:
            continue
        # Deduplicate synonyms across prompts, never distinct instances of one concept.
        label = PROMPT_META.get(d.prompt, (d.prompt, "part"))[0]
        if any(k.prompt != d.prompt and PROMPT_META.get(k.prompt, (k.prompt, ""))[0] == label
               and _iou(k.box, d.box) > DEDUP_IOU for k in kept):
            continue
        kept.append(d)
    segments = []
    for i, d in enumerate(kept, start=1):
        label, kind = PROMPT_META.get(d.prompt, (d.prompt, "part"))
        x1, y1, x2, y2 = d.box
        segments.append(
            Segment(
                id=f"seg_{i}",
                label=label,
                kind=kind,  # type: ignore[arg-type]
                prompt=d.prompt,
                box=[round(x1, 4), round(y1, 4), round(x2 - x1, 4), round(y2 - y1, 4)],
                mask=Mask(format="polygon", points=d.polygon, rings=d.rings) if d.polygon and len(d.polygon) >= 3 else None,
                score=round(d.score, 3),
                source="text",
            )
        )
    return segments


# ---- weak-segment filter (live finding, docs/benchmark.md) -------------------

WEAK_SCORE = 0.6
WEAK_IOU = 0.3
WEAK_CONTAINMENT = 0.6
MAX_PARTS = 3


def _overlaps(weak: Segment, strong: Segment) -> bool:
    """IoU > 0.3 or the weak box lies mostly (> 60 %) inside the stronger one. Boxes are [x, y, w, h]."""
    a = (weak.box[0], weak.box[1], weak.box[0] + weak.box[2], weak.box[1] + weak.box[3])
    b = (strong.box[0], strong.box[1], strong.box[0] + strong.box[2], strong.box[1] + strong.box[3])
    inter = max(0.0, min(a[2], b[2]) - max(a[0], b[0])) * max(0.0, min(a[3], b[3]) - max(a[1], b[1]))
    area = weak.box[2] * weak.box[3]
    return _iou(a, b) > WEAK_IOU or (area > 0 and inter / area > WEAK_CONTAINMENT)


def filter_weak_segments(segments: list[Segment]) -> list[Segment]:
    """Drop weak overlapping damage duplicates and weak parts, keep at most three parts; ids are renumbered.

    Live pulli: `rip` x2 (0.52) sat on three strong `hole` masks; live sneaker: four weak `seam` parts.
    """
    damage = [s for s in segments if s.kind == "damage"]
    kept = []
    for s in segments:
        if s.score < WEAK_SCORE:
            if s.kind == "part":
                continue
            if any(o.score > s.score and _overlaps(s, o) for o in damage if o is not s):
                continue
        kept.append(s)
    parts = sorted((s for s in kept if s.kind == "part"), key=lambda s: s.score, reverse=True)[MAX_PARTS:]
    drop = {id(s) for s in parts}
    kept = [s for s in kept if id(s) not in drop]
    return [s.model_copy(update={"id": f"seg_{i}"}) for i, s in enumerate(kept, start=1)]


def detect_segments(concept: str, segments: list[Segment]) -> list[Segment]:
    """/detect result: damage concepts always yield damage segments, ids `damage_<n>`, weak duplicates dropped."""
    is_damage = concept in DETECT_DAMAGE_CONCEPTS
    if is_damage:
        segments = [s.model_copy(update={"kind": "damage"}) for s in segments]
    out = filter_weak_segments(segments)
    return [s.model_copy(update={"id": f"{s.kind}_{i}"}) for i, s in enumerate(out, start=1)]
