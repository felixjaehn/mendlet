"""Synthetic raw API text -> official decoder -> app-facing segments, all offline."""
import json
from pathlib import Path

import numpy as np
import pytest

from app.sam import bitmap_to_polygon, detections_to_segments, parse_sam_output

FIXTURES = Path(__file__).parent / 'fixtures/sam'
MANIFEST = json.loads((FIXTURES / 'manifest.json').read_text())


def segments(name):
    m = MANIFEST[name]
    return detections_to_segments(parse_sam_output(
        (FIXTURES / f'{name}.txt').read_text(), m['prompt'], m['width'], m['height']))


@pytest.mark.parametrize('name,count', [
    ('thin_tear', 1), ('hole', 1), ('interior_hole', 1),
    ('multi_match', 2), ('zero_match', 0), ('malformed_lines', 2),
])
def test_raw_wire_to_app_segments(name, count):
    segs = segments(name)
    assert len(segs) == count
    assert [s.id for s in segs] == [f'seg_{i+1}' for i in range(count)]
    for s in segs:
        x, y, w, h = s.box
        assert 0 <= x < x+w <= 1 and 0 <= y < y+h <= 1
        assert 0 <= s.score <= 1
        if s.mask:
            assert len(s.mask.points) >= 4
            assert all(x-0.0001 <= u <= x+w+0.0001 and y-0.0001 <= v <= y+h+0.0001
                       for u, v in s.mask.points)
    if name == 'malformed_lines':
        assert segs[0].mask is not None
        assert segs[1].mask is None  # corrupt base85 degrades to a valid box
    else:
        assert all(s.mask is not None for s in segs)


def test_one_pixel_tear_has_nonzero_area_and_correct_offset():
    s = segments('thin_tear')[0]
    assert s.box == pytest.approx([130/640, 180/480, 240/640, 16/480], abs=0.0001)
    p = s.mask.points
    area2 = abs(sum(x*yy - xx*y for (x,y), (xx,yy) in zip(p, p[1:]+p[:1])))
    assert area2 > 0
    assert min(x for x, y in p) == pytest.approx(130/640, abs=0.0001)
    assert max(x for x, y in p) == pytest.approx(370/640, abs=0.0001)
    assert min(y for x, y in p) > 180/480
    assert max(y for x, y in p) < 196/480


def test_single_ring_contract_uses_largest_exterior():
    ring = segments('interior_hole')[0]
    assert len(ring.mask.points) == 4  # internal hole intentionally not representable
    hole = segments('hole')[0]
    # The isolated lint pixel at local (0,0) must not become the chosen polygon.
    assert min(x for x, y in hole.mask.points) > 400/640
    assert len(hole.mask.points) > 4


@pytest.mark.parametrize('mask', [np.ones((1, 500), dtype=np.uint8), np.ones((500, 1), dtype=np.uint8)])
def test_long_single_pixel_lines_survive_without_downsampling(mask):
    p = bitmap_to_polygon(mask)
    assert len(p) == 4
    assert set(map(tuple, p)) == {(0,0), (1,0), (1,1), (0,1)}


@pytest.mark.parametrize('box', [
    'x1=0;y1=0;x2=1;y2=1;w=0;h=0',
    'x1=-1;y1=0;x2=2;y2=1;w=640;h=480',
    'x1=0;y1=0;x2=640;y2=1;w=640;h=480',
    'x1=5;y1=0;x2=2;y2=1;w=640;h=480',
    'x1=0;y1=0;x2=1;y2=1;w=640;h=480;c=1.1',
    'x1=0;y1=0;x2=1;y2=1;w=640;h=480;c=NaN',
    'x1=0;y1=0;x2=1;y2=1;w=100;h=100',
])
def test_invalid_boxes_are_never_shown(box):
    assert parse_sam_output(f'<0f>8<|box;{box}|>', 'tear', 640, 480) == []


def test_extreme_mask_dimensions_do_not_allocate():
    raw = ('<0f>1<|box;x1=1;y1=1;x2=2;y2=2;w=640;h=480|>'
           '<|mask;x=0;y=0;data=999999999,999999999,!bad|>')
    s = detections_to_segments(parse_sam_output(raw, 'tear', 640, 480))
    assert len(s) == 1 and s[0].mask is None
