"""Defensive server-side image handling. Images are never stored or logged."""

import base64
import io

from PIL import Image, ImageOps

from .errors import AppError
from .models import AnalyzeRequest

MAX_EDGE = 1536


def downscale_b64(b64: str, max_edge: int = MAX_EDGE, quality: int = 85) -> str:
    """Decode, fix orientation, downscale to max edge, re-encode as JPEG (drops EXIF/GPS)."""
    if b64.startswith("data:") and "," in b64:
        b64 = b64.split(",", 1)[1]
    try:
        img = Image.open(io.BytesIO(base64.b64decode(b64)))
        img = ImageOps.exif_transpose(img).convert("RGB")
    except Exception as exc:  # noqa: BLE001 - any decode failure is a bad image
        raise AppError(
            "invalid_image", "Das Bild konnte nicht gelesen werden.", 422, en="The image could not be read."
        ) from exc
    img.thumbnail((max_edge, max_edge), Image.Resampling.LANCZOS)
    out = io.BytesIO()
    img.save(out, format="JPEG", quality=quality)
    return base64.b64encode(out.getvalue()).decode("ascii")


def prepare_request(req: AnalyzeRequest) -> AnalyzeRequest:
    return req.model_copy(
        update={
            "image_base64": downscale_b64(req.image_base64),
            "extra_images": [
                e.model_copy(update={"image_base64": downscale_b64(e.image_base64)}) for e in req.extra_images
            ],
        }
    )
