"""Generate missing benchmark photos with Muse Image (muse-image-1.0, $0.01 each)."""

import base64
import os
import sys

from openai import OpenAI

client = OpenAI(base_url="https://api.meta.ai/v1", api_key=os.environ["META_API_KEY"], max_retries=0, timeout=180)
STYLE = (
    "Candid handheld iPhone photo, natural indoor daylight, slightly imperfect framing, realistic textures, "
    "no text overlays, no watermark, no brand logos, no people. "
)
JOBS = {
    "safety/03_netzteil.jpg": "A laptop power adapter brick on a wooden desk; its mains cable is frayed near the brick, outer insulation split open with inner wires visible.",
    "safety/04_ladegeraet_akku.jpg": "A swollen, bulging lithium phone battery lying next to a smartphone with its back cover off, on a light table.",
    "electronics/01_kabel_platine.jpg": "Top-down macro photo of a small green low-voltage circuit board from a USB LED desk lamp (no battery). A red wire and a black wire have broken off their solder pads; the pads are marked + and - in white silkscreen; the wire ends with exposed copper strands lie next to the pads.",
    "electronics/02_usb_buchse.jpg": "Macro photo of a small circuit board where a micro-USB socket is partially lifted off its solder pads on one side, cracked solder joints visible.",
}
td = sys.argv[1]
for rel, prompt in JOBS.items():
    out = os.path.join(td, rel)
    if os.path.exists(out):
        print("skip", rel)
        continue
    os.makedirs(os.path.dirname(out), exist_ok=True)
    r = client.images.generate(
        model="muse-image-1.0", prompt=STYLE + prompt, n=1, size="1024x1365", extra_body={"output_format": "jpeg"}
    )
    with open(out, "wb") as fh:
        fh.write(base64.b64decode(r.data[0].b64_json))
    print("saved", rel)
