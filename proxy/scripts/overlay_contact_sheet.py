"""Contact sheet for the manual "overlay on damage" check: every benchmark photo with its masks.

Usage:  uv run python scripts/overlay_contact_sheet.py ../docs/benchmark-runs/2026-10-29 out.jpg
Damage masks red, parts blue, solder pads yellow. Reads the raw responses written by run_benchmark.py --dump.
"""

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

PROXY_DIR = Path(__file__).resolve().parent.parent
TESTDATA = PROXY_DIR.parent / "testdata"
TILE = 420


def tile(case: dict, resp: dict) -> Image.Image:
    im = ImageOps.exif_transpose(Image.open(TESTDATA / case["image"])).convert("RGB")
    im.thumbnail((TILE, TILE))
    w, h = im.size
    d = ImageDraw.Draw(im, "RGBA")
    for s in resp.get("segments", []):
        rgb = (255, 210, 0) if s.get("polarity") else (230, 60, 30) if s["kind"] == "damage" else (60, 120, 230)
        rings = (s.get("mask") or {}).get("rings") or ([{"points": s["mask"]["points"]}] if s.get("mask") else [])
        for ring in rings:
            pts = [(x * w, y * h) for x, y in ring["points"]]
            if len(pts) >= 3:
                d.polygon(pts, fill=rgb + (80,), outline=rgb + (255,))
    canvas = Image.new("RGB", (TILE, TILE + 28), (24, 24, 24))
    canvas.paste(im, ((TILE - w) // 2, 0))
    label = f"{case['id']}  {resp.get('risk_level', '')}  segs={len(resp.get('segments', []))}"
    ImageDraw.Draw(canvas).text((6, TILE + 8), label, fill=(240, 240, 240))
    return canvas


def main() -> None:
    dump, out = Path(sys.argv[1]), Path(sys.argv[2])
    cases = json.loads((TESTDATA / "cases.json").read_text(encoding="utf-8"))["cases"]
    tiles = [
        tile(c, json.loads((dump / f"{c['id']}.json").read_text(encoding="utf-8")))
        for c in cases
        if (dump / f"{c['id']}.json").is_file()
    ]
    cols = 4
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * TILE, rows * (TILE + 28)), (0, 0, 0))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * TILE, (i // cols) * (TILE + 28)))
    sheet.save(out, quality=85)
    print(f"{len(tiles)} tiles -> {out}")


if __name__ == "__main__":
    main()
