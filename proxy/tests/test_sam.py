import numpy as np
import pytest

from app.sam import SamDetection, bitmap_to_polygon, detections_to_segments, parse_sam_output, trace_contour

meta = pytest.importorskip("meta_sam_parser")


def test_polygon_of_rectangle():
    m = np.zeros((20, 40), dtype=np.uint8)
    m[5:15, 8:32] = 1
    poly = bitmap_to_polygon(m)
    assert len(poly) >= 4
    xs, ys = [p[0] for p in poly], [p[1] for p in poly]
    assert 0.18 < min(xs) < 0.24 and 0.76 < max(xs) < 0.82
    assert 0.22 < min(ys) < 0.28 and 0.70 < max(ys) < 0.78


def test_polygon_of_thin_line_and_nonconvex():
    m = np.zeros((30, 60), dtype=np.uint8)
    m[14:17, 5:55] = 1  # thin tear
    poly = bitmap_to_polygon(m)
    assert len(poly) >= 4
    l = np.zeros((20, 20), dtype=np.uint8)
    l[2:18, 2:6] = 1
    l[14:18, 2:18] = 1  # L shape
    assert len(trace_contour(l)) > 20


def test_empty_mask():
    assert bitmap_to_polygon(np.zeros((5, 5), dtype=np.uint8)) == []


def _encode(raster: np.ndarray, w: int, h: int) -> str:
    from meta_sam_parser._mask_codec import _encode_raster

    return _encode_raster([int(v) for v in raster.flatten()], w, h)


def test_parse_synthetic_sam_output_with_mask():
    """Synthetic example. ASSUMPTION (UNBESTÄTIGT): mask = crop of the box placed at (x1, y1)."""
    img_w, img_h = 200, 100
    x1, y1, x2, y2 = 40, 30, 139, 49  # 100 x 20 box
    mask = np.zeros((20, 100), dtype=np.uint8)
    mask[8:12, :] = 1  # thin horizontal tear inside the box
    payload = _encode(mask, 100, 20)
    text = (f"<0f>3<|box;x1={x1};y1={y1};x2={x2};y2={y2};w={img_w};h={img_h};c=0.9|>"
            f"<|mask;x=0;y=0;c=0.9;data=20,100,{payload}|>")
    dets = parse_sam_output(text, "tear", img_w, img_h)
    assert len(dets) == 1 and dets[0].score == pytest.approx(0.9)
    bx1, by1, bx2, by2 = dets[0].box
    assert bx1 == pytest.approx(0.2) and by1 == pytest.approx(0.3)
    ys = [p[1] for p in dets[0].polygon]
    xs = [p[0] for p in dets[0].polygon]
    assert 0.3 + 0.07 < min(ys) and max(ys) < 0.3 + 0.13  # rows 8..12 of 100 px height -> y 0.38..0.42
    assert 0.2 <= min(xs) < 0.22 and 0.68 < max(xs) <= 0.7


def test_boxes_only_fallback_parse():
    text = "<0f>1<|box;x1=10;y1=20;x2=59;y2=39;w=100;h=100;c=0.7|>"
    dets = parse_sam_output(text, "hole", 100, 100)
    assert dets and dets[0].polygon is None


def test_dedupe_and_ids():
    a = SamDetection("tear", 0.9, (0.1, 0.1, 0.5, 0.2))
    b = SamDetection("rip", 0.8, (0.11, 0.1, 0.5, 0.2))  # same label (Riss), overlapping -> dropped
    c = SamDetection("hole", 0.7, (0.6, 0.6, 0.7, 0.7))
    d = SamDetection("button", 0.1, (0.0, 0.0, 0.1, 0.1))  # below min score
    segs = detections_to_segments([a, b, c, d])
    assert [s.id for s in segs] == ["seg_1", "seg_2"]
    assert [s.prompt for s in segs] == ["tear", "hole"]
    assert segs[0].kind == "damage" and segs[0].box[2] == pytest.approx(0.4)
