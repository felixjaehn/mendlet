"""Deterministic mock client (MOCK_MODE): realistic German fixtures with realistic delays."""

import asyncio
import base64
import io
import re

import numpy as np
from PIL import Image

from . import mock_data as md
from .errors import AppError
from .images import downscale_b64
from .models import (
    AfterPreviewRequest,
    AfterPreviewResponse,
    AnalyzeRequest,
    ClassifyResult,
    DiagnosePlan,
    RefineRequest,
    Segment,
    StepHelpRequest,
    StepHelpResponse,
    TrackRequest,
    TrackResponse,
)
from .sam import bitmap_to_rings
from .video import prepare_video

SCENARIOS = {
    "textile_tear_needs_label", "textile_tear", "textile_hole", "textile_open_seam", "textile_button",
    "shoe_sole", "battery_jacket", "helmet", "unsupported",
    "textile_grounding", "textile_multi", "textile_rings",
}

# keyword (lowercase) -> scenario; first match wins
_KEYWORDS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(p), s)
    for p, s in [
        (r"akku|beheizbar|heizjacke|lithium", "battery_jacket"),
        (r"helm", "helmet"),
        (r"fahrrad|fahrradkette|möbel|stuhl|tisch", "unsupported"),
        (r"sohle|schuh|sneaker|stiefel|absatz", "shoe_sole"),
        (r"knopf", "textile_button"),
        (r"loch|stopf|pullover", "textile_hole"),
        (r"naht offen|offene naht|naht ist|nähte", "textile_open_seam"),
    ]
]


def pick_scenario(req: AnalyzeRequest) -> str:
    """Scenario hint field first, then keywords in user_note, default textile (tear)."""
    hint = (req.mock_scenario or "").strip().lower()
    if hint == "textile":
        hint = ""
    scenario = hint if hint in SCENARIOS else ""
    if not scenario:
        note = req.note.lower()
        scenario = next((s for p, s in _KEYWORDS if p.search(note)), "textile_tear_needs_label")
    # second round of the textile hero case: label answer changes the result
    if scenario == "textile_tear_needs_label" and req.is_followup_round:
        scenario = "textile_tear"
    return scenario


def _stretch_from_answers(req: AnalyzeRequest) -> bool:
    """Mock 'label reading': an answer naming 100 % cotton means no stretch, otherwise Elasthan."""
    text = " ".join(a.text for a in req.answers).lower()
    return not re.search(r"100\s?%\s?baumwolle", text)


class MockClient:
    def __init__(self, delay_scale: float = 1.0) -> None:
        self.scale = delay_scale
        self.plan_delay = 0.8 * delay_scale

    async def _sleep(self, seconds: float) -> None:
        if self.scale > 0:
            await asyncio.sleep(seconds * self.scale)

    async def classify(self, req: AnalyzeRequest) -> ClassifyResult:
        await self._sleep(0.7)
        scenario = pick_scenario(req)
        if scenario.startswith("shoe"):
            return md.CLASSIFY["shoe"]
        if scenario.startswith("textile"):
            return md.CLASSIFY["textile"]
        return md.CLASSIFY[scenario]

    async def segment(self, req: AnalyzeRequest, category: str, prompts: list[str]) -> list[Segment]:
        await self._sleep(1.1)
        return md.segments(pick_scenario(req))

    async def diagnose(self, req: AnalyzeRequest, cls: ClassifyResult, segments: list[Segment]) -> DiagnosePlan:
        await self._sleep(1.2)
        scenario = pick_scenario(req)
        if scenario == "textile_tear_needs_label":
            return md.textile_tear_needs_label()
        if scenario in {"textile_tear", "textile_grounding", "textile_multi", "textile_rings"}:
            return md.textile_tear(stretch=_stretch_from_answers(req))
        builders = {
            "textile_hole": md.textile_hole,
            "textile_open_seam": md.textile_open_seam,
            "textile_button": md.textile_button,
            "shoe_sole": md.shoe_sole,
        }
        return builders[scenario]()

    async def step_help(self, req: StepHelpRequest) -> StepHelpResponse:
        await self._sleep(0.8)
        issue = req.issue_text.lower()
        title = req.step.title
        if re.search(r"rauch|heiß|heiss|akku|brenn", issue):
            return StepHelpResponse(
                answer="Brich den Schritt sofort ab, nimm das Teil weg von Hitzequellen und lüfte den Raum. Mach erst weiter, wenn alles abgekühlt ist.",
                retry_hint=None, escalate=True)
        if re.search(r"kleber|haftet|klebt", issue):
            return StepHelpResponse(
                answer=f"Beim Schritt \"{title}\" haftet der Kleber meist nicht, weil die Fläche fettig oder zu glatt ist oder die Schichten zu früh zusammenkamen.",
                retry_hint="Raue die Flächen erneut an, entfette sie und lass den Kleber vor dem Zusammendrücken 10–15 Minuten ablüften.", escalate=False)
        if re.search(r"faden|reißt|reisst|verknot|verdrill", issue):
            return StepHelpResponse(
                answer="Der Faden verdrillt oder reißt, wenn er zu lang ist oder zu stramm gezogen wird. Kürze ihn auf etwa 50 cm und ziehe ihn gleichmäßig an.",
                retry_hint="Fädle neu ein, mach den Knoten kleiner und führe die Nadel in gleichmäßigen Stichen weiter.", escalate=False)
        if re.search(r"nadel|durch|dick|hart|steif", issue):
            return StepHelpResponse(
                answer="Bei dickem Stoff schiebst du die Nadel mit dem Fingerhut durch und stichst senkrecht ein. Ein dünnes Stück Seife auf der Nadel hilft, aber nicht zwingend.",
                retry_hint="Versuche kleinere Stiche und stich nur durch eine Lage, wenn die Naht sichtbar bleiben darf.", escalate=False)
        return StepHelpResponse(
            answer=f"Zum Schritt \"{title}\": Geh ihn noch einmal langsam durch und vergleiche, was der Schritt verlangt, mit deinem Ergebnis. Die übrigen Schritte bleiben unverändert.",
            retry_hint="Mach ein Foto der Stelle von nahem und schicke es mit, dann sehe ich genauer hin.", escalate=False)

    async def transcribe(self, wav: bytes, duration_s: float) -> str:
        await self._sleep(0.6)
        return "Am Hosenbein ist ein Riss entlang der Naht, etwa sechs Zentimeter lang."

    async def ground(self, req: AnalyzeRequest, category: str) -> list[Segment]:
        await self._sleep(0.6)
        return [md.segments("shoe_sole" if category == "shoe" else "textile_tear")[1].model_copy(
            update={"source": "grounding"})]

    async def refine(self, req: RefineRequest) -> Segment:
        image = downscale_b64(req.image_base64)
        with Image.open(io.BytesIO(base64.b64decode(image))) as photo:
            width, height = photo.size
        yy, xx = np.indices((height, width))
        mask = np.zeros((height, width), dtype=bool)
        if req.box:
            x, y, w, h = req.box
            mask[int(y * height):max(int(y * height) + 1, int(np.ceil((y + h) * height))),
                 int(x * width):max(int(x * width) + 1, int(np.ceil((x + w) * width)))] = True
        for label in ("positive", "negative"):
            for p in (p for p in req.points if p.label == label):
                cx, cy = min(width - 1, int(p.x * width)), min(height - 1, int(p.y * height))
                region = ((xx - cx) / max(1, width * 0.04)) ** 2 + ((yy - cy) / max(1, height * 0.04)) ** 2 <= 1
                mask[region] = label == "positive"
        rings = bitmap_to_rings(mask)
        if not rings:
            raise AppError("no_segment", "Die markierte Stelle konnte nicht erkannt werden. Bitte markiere sie erneut.", 422)
        result = md.seg("seg_1", req.label, "damage", req.label, 0.9, rings[0].points)
        ys, xs = np.nonzero(mask)
        result.box = [min(xs) / width, min(ys) / height, (max(xs) + 1 - min(xs)) / width, (max(ys) + 1 - min(ys)) / height]
        result.mask.rings = rings
        result.source = "tap"
        return result

    async def track(self, req: TrackRequest) -> TrackResponse:
        prepare_video(req.video_base64)
        await self._sleep(0.8)
        return md.tracking(req.concept)

    async def after_preview(self, req: AfterPreviewRequest) -> AfterPreviewResponse:
        image = downscale_b64(req.image_base64)
        with Image.open(io.BytesIO(base64.b64decode(image))) as photo:
            photo = photo.convert("RGB")
            # A small, deterministic local change; this fixture is not a generated repair.
            y = photo.height // 2
            for x in range(photo.width // 3, max(photo.width // 3 + 1, 2 * photo.width // 3)):
                photo.putpixel((x, y), tuple(v + 3 if v <= 252 else v - 3 for v in photo.getpixel((x, y))))
            out = io.BytesIO()
            photo.save(out, format="PNG")
        return AfterPreviewResponse(image_base64=base64.b64encode(out.getvalue()).decode("ascii"), model="muse-image-1.0")
