"""Live probe: Spark JSON with image + SAM concept sweep. Run from repair-assistant/proxy with uv run."""

import base64
import io
import json
import os
import sys
import time

from openai import OpenAI
from PIL import Image, ImageOps

sys.path.insert(0, os.getcwd())
from app.sam import parse_sam_output  # noqa: E402

client = OpenAI(base_url="https://api.meta.ai/v1", api_key=os.environ["META_API_KEY"], max_retries=0, timeout=120)
TD = os.path.join(os.getcwd(), "..", "testdata")


def load(path, side=1024, fmt="PNG"):
    im = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    im.thumbnail((side, side))
    buf = io.BytesIO()
    im.save(buf, fmt, quality=88)
    mime = "image/png" if fmt == "PNG" else "image/jpeg"
    return im.size, f"data:{mime};base64," + base64.b64encode(buf.getvalue()).decode()


def spark(path):
    _, url = load(path, 1024, "JPEG")
    schema = {
        "type": "object",
        "properties": {
            "category": {"type": "string"},
            "damage": {"type": "string"},
            "box_0_1000": {"type": "array", "items": {"type": "integer"}},
        },
        "required": ["category", "damage", "box_0_1000"],
    }
    t = time.time()
    r = client.chat.completions.create(
        model="muse-spark-1.3",
        max_completion_tokens=2048,
        response_format={"type": "json_schema", "json_schema": {"name": "probe", "schema": schema}},
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": "Classify the object and locate the damage. box_0_1000 = [x1,y1,x2,y2] on a 0-1000 grid.",
                    },
                    {"type": "image_url", "image_url": {"url": url}},
                ],
            }
        ],
    )
    c = r.choices[0]
    print(f"SPARK {os.path.basename(path)} {time.time() - t:.1f}s finish={c.finish_reason} usage={r.usage}")
    print("  content:", (c.message.content or "")[:400])


def sam(path, concept):
    (w, h), url = load(path, 1024, "PNG")
    t = time.time()
    text = ""
    with client.responses.stream(
        model="sam-3.1",
        metadata={"include_confidence": "true", "mask_encoding": "one_bit"},
        input=[
            {
                "type": "message",
                "role": "user",
                "content": [{"type": "input_text", "text": concept}, {"type": "input_image", "image_url": url}],
            }
        ],
    ) as s:
        for ev in s:
            if ev.type == "response.output_text.delta":
                text += ev.delta
    dets = parse_sam_output(text, concept, w, h)
    scores = [round(getattr(d, "score", 0) or 0, 2) for d in dets]
    print(
        f"SAM {os.path.basename(path):24s} {concept!r:22s} {time.time() - t:4.1f}s matches={len(dets)} scores={scores}"
    )


def geo(path, box1000, points, out):
    """SAM with a geometric prompt: box on 0-1000 grid (x1,y1,x2,y2) plus optional points [(x,y,label)] on 0-1000."""
    from PIL import ImageDraw

    from app.models import RefinePoint
    from app.sam import geometric_prompt

    (w, h), url = load(path, 1024, "PNG")
    x1, y1, x2, y2 = [v / 1000 for v in box1000]
    pts = [RefinePoint(x=px / 1000, y=py / 1000, label=lab) for px, py, lab in points]
    prompt = geometric_prompt(w, h, pts, [x1, y1, x2 - x1, y2 - y1])
    t = time.time()
    text = ""
    with client.responses.stream(
        model="sam-3.1",
        metadata={"include_confidence": "true", "mask_encoding": "one_bit"},
        input=[
            {
                "type": "message",
                "role": "user",
                "content": [{"type": "input_text", "text": prompt}, {"type": "input_image", "image_url": url}],
            }
        ],
    ) as s:
        for ev in s:
            if ev.type == "response.output_text.delta":
                text += ev.delta
    dets = parse_sam_output(text, "damage", w, h)
    im = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    im.thumbnail((1024, 1024))
    d = ImageDraw.Draw(im, "RGBA")
    d.rectangle([x1 * w, y1 * h, x2 * w, y2 * h], outline=(255, 255, 0, 255), width=3)
    for px, py, lab in points:
        c = (0, 255, 0, 255) if lab == "positive" else (255, 0, 0, 255)
        d.ellipse([px / 1000 * w - 8, py / 1000 * h - 8, px / 1000 * w + 8, py / 1000 * h + 8], fill=c)
    for det in dets:
        if det.polygon:
            poly = [(p[0] * w, p[1] * h) for p in det.polygon]
            d.polygon(poly, fill=(226, 85, 43, 90), outline=(226, 85, 43, 255))
    im.save(out)
    print(
        f"GEO {os.path.basename(path)} {time.time() - t:.1f}s matches={len(dets)} scores={[round(x.score, 2) for x in dets]} polypts={[len(x.polygon or []) for x in dets]} -> {out}"
    )


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "geo":
        box = json.loads(sys.argv[3])
        pts = json.loads(sys.argv[4]) if len(sys.argv) > 4 else []
        geo(os.path.join(TD, sys.argv[2]), box, pts, sys.argv[5] if len(sys.argv) > 5 else "/tmp/geo.png")
    elif mode == "spark":
        spark(os.path.join(TD, sys.argv[2]))
    else:
        img = os.path.join(TD, sys.argv[2])
        for c in sys.argv[3:]:
            try:
                sam(img, c)
            except Exception as e:  # keep sweeping
                print(f"SAM {c!r} ERROR {type(e).__name__}: {str(e)[:200]}")
