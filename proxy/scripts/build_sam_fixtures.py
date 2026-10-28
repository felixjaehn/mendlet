"""Rebuild synthetic wire fixtures offline using the installed official codec.

The codec currently exposes only a private encoder; committed fixtures also work
when that helper changes. They are synthetic, never presented as live API output.
"""
import json
from pathlib import Path

import numpy as np
from meta_sam_parser._mask_codec import _encode_raster

OUT = Path(__file__).resolve().parents[1] / 'tests/fixtures/sam'
W, H = 640, 480


def record(oid, box, mask, score=0.93):
    x, y, w, h = box
    mh, mw = mask.shape
    encoded = _encode_raster(mask.reshape(-1).tolist(), mw, mh)
    return (f'{oid}<|box;x1={x};y1={y};x2={x+w-1};y2={y+h-1};w={W};h={H};c={score}|>'
            f'<|mask;x=0;y=0;c={score};data={mh},{mw},{encoded}|>')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    tear = np.zeros((16, 240), dtype=np.uint8)
    for x in range(240):
        tear[6 + int(2 * np.sin(x / 28)), x] = 1
    hole = np.zeros((64, 80), dtype=np.uint8)
    yy, xx = np.indices(hole.shape)
    hole[((xx-40)/34)**2 + ((yy-32)/27)**2 <= 1] = 1
    # Disconnected lint must not displace the main contour in raster order.
    hole[0, 0] = 1
    ring = np.ones((40, 60), dtype=np.uint8)
    ring[10:30, 15:45] = 0  # the single-ring app contract intentionally omits this interior
    a = record(7, (130, 180, 240, 16), tear)
    b = record(42, (400, 300, 80, 64), hole, 0.87)
    data = {
        'thin_tear': ('tear', '<0f>' + a),
        'hole': ('hole', '<0f>' + b),
        'interior_hole': ('hole', '<0f>' + record(9, (30, 40, 60, 40), ring)),
        'multi_match': ('tear', '<0f>' + a + ',' + b),
        'zero_match': ('tear', ''),
        'malformed_lines': ('tear', 'not SAM\n<1f>' + a + '\n<0f>bad record\n<0f>' + a
                            + ',8<|box;x1=0;y1=0;x2=9;y2=9;w=640;h=480;c=0.8|>'
                            + '<|mask;x=0;y=0;c=0.8;data=10,10,!BROKEN|>\n'
                            + '<0f>99<|box;x1=0;y1=0;x2=3;y2=3;w=0;h=0;c=NaN|>'),
    }
    manifest = {}
    for name, (prompt, raw) in data.items():
        (OUT / f'{name}.txt').write_text(raw + ('\n' if raw else ''), encoding='utf-8')
        manifest[name] = {'prompt': prompt, 'width': W, 'height': H, 'synthetic': True}
    (OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
