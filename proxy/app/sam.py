"""SAM 3.1 helpers: prompts, output-text parsing, mask -> polygon conversion, de-duplication.

SAM answers with special-token text (see docs/api-notes.md section 2), one concept per request.
App-facing mask format is a polygon in normalized image coordinates:
    {"format": "polygon", "points": [[x, y], ...]}
"""

import math
import re
from dataclasses import dataclass

import numpy as np

from .models import Mask, Segment

# Short English noun phrases (SAM handles one concept per request).
SEGMENT_PROMPTS: dict[str, list[str]] = {
    "textile": ["tear", "rip", "hole", "open seam", "frayed edge", "garment", "button"],
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
    "cable": ("Kabel", "part"),
    "connector": ("Stecker", "part"),
    "housing": ("Gehäuse", "part"),
}

MIN_SCORE = 0.25
DEDUP_IOU = 0.6
MAX_SEGMENTS = 8


@dataclass
class SamDetection:
    prompt: str
    score: float
    box: tuple[float, float, float, float]  # x1, y1, x2, y2 normalized
    polygon: list[list[float]] | None = None  # normalized


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


def bitmap_to_polygon(raster: np.ndarray, max_points: int = 80) -> list[list[float]]:
    """Largest exterior ring at pixel edges, normalized to the raster.

    Do not downsample: a one-pixel tear must retain its area. The app contract has
    one polygon, so interior holes and smaller disconnected islands are omitted.
    """
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
        return abs(sum(x * yy - xx * y for (x, y), (xx, yy) in zip(ring, ring[1:] + ring[:1])))

    pts = max(rings, key=area)
    tol = 0.2
    simp = _simplify_closed(pts, tol)
    while len(simp) > max_points:
        tol *= 1.5
        simp = _simplify_closed(pts, tol)
    if len(simp) < 3 or not area(simp):
        return []
    return [[round(x / w, 6), round(y / h, 6)] for x, y in simp]


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


def parse_sam_output(text: str, prompt: str, img_w: int, img_h: int) -> list[SamDetection]:
    """Documented key=value wire records -> validated boxes and polygons.

    The official library confirms box-local half-open mask bounds offline. Actual
    non-stream response envelopes and placement on real photos are UNBESTÄTIGT.
    Invalid masks degrade to boxes; invalid coordinates/frames are discarded.
    """
    if img_w <= 0 or img_h <= 0:
        return []
    try:
        from meta_sam_parser import CompletedOutcome, decode_mask_to_raster, image_segmentation_format
    except ImportError:
        image_segmentation_format = None
    dets = []
    for line in text.splitlines():
        if not line.startswith("<0f>"):
            continue
        for match in _RECORD_RE.finditer(line[4:].strip()):
            oid, box_token, mask_token = match.groups()
            parsed = _box_fields(box_token, img_w, img_h)
            if parsed is None:
                continue
            score, box = parsed
            det = SamDetection(prompt, score, box)
            dets.append(det)
            if mask_token is None or image_segmentation_format is None:
                continue
            # Bound allocations before the library decodes a claimed raster size.
            dims = re.search(r";data=(\d+),(\d+),[!~]", mask_token)
            if not dims or not (0 < int(dims[1]) * int(dims[2]) <= min(img_w * img_h, 4_000_000)):
                continue
            try:
                parser = image_segmentation_format().create_parser()
                parser.push(f"<0f>{oid}{box_token}{mask_token}\n")
                records = parser.finish(CompletedOutcome()).result.records
                mrec = next((r for r in records if r.kind == "mask"), None)
                if mrec is None:
                    continue
                raster = np.frombuffer(decode_mask_to_raster(mrec.mask), dtype=np.uint8)
                raster = raster.reshape(mrec.mask.height, mrec.mask.width)
                b = mrec.bounds
                det.polygon = [
                    [round((b.left + u * (b.right - b.left)) / img_w, 6),
                     round((b.top + v * (b.bottom - b.top)) / img_h, 6)]
                    for u, v in bitmap_to_polygon(raster)
                ] or None
            except (ValueError, ArithmeticError):
                # InvalidSegmentationMaskError is normally retained as a parser
                # diagnostic. No raw payloads are logged or exposed to the app.
                continue
    return dets


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
        # same meaning (same label) and heavy overlap = duplicate
        label = PROMPT_META.get(d.prompt, (d.prompt, "part"))[0]
        if any(PROMPT_META.get(k.prompt, (k.prompt, ""))[0] == label and _iou(k.box, d.box) > DEDUP_IOU for k in kept):
            continue
        kept.append(d)
    segments = []
    for i, d in enumerate(kept[:MAX_SEGMENTS], start=1):
        label, kind = PROMPT_META.get(d.prompt, (d.prompt, "part"))
        x1, y1, x2, y2 = d.box
        segments.append(
            Segment(
                id=f"seg_{i}",
                label=label,
                kind=kind,  # type: ignore[arg-type]
                prompt=d.prompt,
                box=[round(x1, 4), round(y1, 4), round(x2 - x1, 4), round(y2 - y1, 4)],
                mask=Mask(format="polygon", points=d.polygon) if d.polygon and len(d.polygon) >= 3 else None,
                score=round(d.score, 3),
            )
        )
    return segments
