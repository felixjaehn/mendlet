"""SAM 3.1 helpers: prompts, output-text parsing, mask -> polygon conversion, de-duplication.

SAM answers with special-token text (see docs/api-notes.md section 2), one concept per request.
App-facing mask format is a polygon in normalized image coordinates:
    {"format": "polygon", "points": [[x, y], ...]}
"""

import re
from dataclasses import dataclass

import numpy as np
from PIL import Image

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
    """Binary raster (H x W) -> simplified polygon in coordinates normalized to the raster (0..1)."""
    h, w = raster.shape
    scale = min(1.0, 160 / max(h, w))
    if scale < 1.0:
        img = Image.fromarray((raster.astype(np.uint8)) * 255).resize(
            (max(1, round(w * scale)), max(1, round(h * scale))), Image.Resampling.NEAREST
        )
        raster = np.asarray(img) > 127
        h, w = raster.shape
    contour = trace_contour(raster)
    if len(contour) < 3:
        return []
    pts = [(x + 0.5, y + 0.5) for y, x in contour]
    tol = 0.6
    simp = _simplify_closed(pts, tol)
    while len(simp) > max_points:
        tol *= 1.5
        simp = _simplify_closed(pts, tol)
    return [[round(x / w, 4), round(y / h, 4)] for x, y in simp]


# ---- SAM output text -> detections -------------------------------------------

_BOX_RE = re.compile(r"<\|box;x1=(\d+);y1=(\d+);x2=(\d+);y2=(\d+);w=(\d+);h=(\d+)(?:;c=([\d.]+))?\|>")


def _parse_boxes_only(text: str, prompt: str) -> list[SamDetection]:
    """Fallback parser: boxes + scores only (no masks)."""
    out = []
    for m in _BOX_RE.finditer(text):
        x1, y1, x2, y2, w, h = (int(v) for v in m.groups()[:6])
        out.append(
            SamDetection(prompt, float(m.group(7) or 0.5), (x1 / w, y1 / h, min(1.0, (x2 + 1) / w), min(1.0, (y2 + 1) / h)))
        )
    return out


def parse_sam_output(text: str, prompt: str, img_w: int, img_h: int) -> list[SamDetection]:
    """Parse SAM output_text for one prompt using the official meta-sam-parser; boxes-only fallback.

    TODO(UNBESTÄTIGT, see docs/api-notes.md): the mask is assumed to be the crop of the box placed at
    (x1, y1). meta-sam-parser exposes this as `bounds`; verify against the first live response.
    """
    try:
        from meta_sam_parser import CompletedOutcome, decode_mask_to_raster, image_segmentation_format

        parser = image_segmentation_format().create_parser()
        parser.push(text + "\n")
        result = parser.finish(CompletedOutcome()).result
        boxes: dict[str, object] = {}
        masks: dict[str, object] = {}
        for rec in result.records:
            if rec.kind == "box":
                boxes[rec.object_id] = rec
            elif rec.kind == "mask":
                masks[rec.object_id] = rec
        dets: list[SamDetection] = []
        for oid, box in boxes.items():
            det = SamDetection(
                prompt,
                box.confidence if box.confidence is not None else 0.5,  # type: ignore[attr-defined]
                (box.left / img_w, box.top / img_h, box.right / img_w, box.bottom / img_h),  # type: ignore[attr-defined]
            )
            mrec = masks.get(oid)
            if mrec is not None:
                raster = np.frombuffer(decode_mask_to_raster(mrec.mask), dtype=np.uint8)  # type: ignore[attr-defined]
                raster = raster.reshape(mrec.mask.height, mrec.mask.width)  # type: ignore[attr-defined]
                b = mrec.bounds  # type: ignore[attr-defined]
                det.polygon = [
                    [round((b.left + u * (b.right - b.left)) / img_w, 4), round((b.top + v * (b.bottom - b.top)) / img_h, 4)]
                    for u, v in bitmap_to_polygon(raster)
                ]
            dets.append(det)
        if dets:
            return dets
    except ImportError:
        pass
    return _parse_boxes_only(text, prompt)


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
