"""Model client interface and the real Meta Model API implementation (see docs/api-notes.md)."""

import asyncio
import base64
import hashlib
import io
import json
import logging
from typing import Protocol, TypeVar

import httpx
from openai import APIConnectionError, APIError, APIStatusError, APITimeoutError, AsyncOpenAI
from PIL import Image
from pydantic import BaseModel

from .audio import ensure_wav
from .budget import Budget, image_cost, muse_cost, sam_cost, sam_video_cost, transcribe_cost
from .cache import ModelCache
from .config import Settings
from .errors import AppError, BudgetExceeded, ModelOutputError
from .images import downscale_b64
from .models import (
    AfterPreviewRequest,
    AfterPreviewResponse,
    AnalyzeRequest,
    ClassifyResult,
    DiagnosePlan,
    GroundingResult,
    RefineRequest,
    Segment,
    StepHelpRequest,
    StepHelpResponse,
    TrackRequest,
    TrackResponse,
)
from .parsing import call_validated, parse_model_json
from .prompts import inline_schema, load_prompt, prompt_version
from .sam import SamDetection, detections_to_segments, geometric_prompt, parse_sam_output, parse_sam_video
from .video import prepare_video

log = logging.getLogger("proxy.client")
T = TypeVar("T", bound=BaseModel)


class ModelClient(Protocol):
    plan_delay: float  # seconds the pipeline waits in the "plan" stage (mock only)

    async def classify(self, req: AnalyzeRequest) -> ClassifyResult: ...
    async def segment(self, req: AnalyzeRequest, category: str, prompts: list[str]) -> list[Segment]: ...
    async def diagnose(self, req: AnalyzeRequest, cls: ClassifyResult, segments: list[Segment]) -> DiagnosePlan: ...
    async def step_help(self, req: StepHelpRequest) -> StepHelpResponse: ...
    async def transcribe(self, wav: bytes, duration_s: float) -> str: ...
    async def refine(self, req: RefineRequest) -> Segment: ...
    async def ground(self, req: AnalyzeRequest, category: str) -> list[Segment]: ...
    async def track(self, req: TrackRequest) -> TrackResponse: ...
    async def after_preview(self, req: AfterPreviewRequest) -> AfterPreviewResponse: ...


def _data_url(b64: str) -> str:
    return f"data:image/jpeg;base64,{b64}"


def preview_prompt(req: AfterPreviewRequest) -> str:
    stitch = {"ladder_stitch": "ladder stitch", "running_stitch": "running stitch",
              "darning": "darning", "whip_stitch": "whip stitch"}[req.stitch_type]
    return (f"Same photo, show the repaired state of this damage: {req.diagnosis_summary}. "
            f"Neatly close or mend it with {stitch} in matching thread. "
            "Keep the same object, material, lighting, perspective and background; nothing else changed.")


class RealMetaClient:
    plan_delay = 0.0

    def __init__(self, settings: Settings, budget: Budget, http_client: httpx.AsyncClient | None = None) -> None:
        self.s = settings
        self.budget = budget
        self.cache = ModelCache(settings.cache_dir, settings.cache_model_calls)
        # SDK defaults retry billable requests. Application validation owns its one retry.
        self.http = http_client or httpx.AsyncClient(timeout=60.0)
        self.oai = AsyncOpenAI(
            api_key=settings.meta_api_key, base_url=settings.base_url, timeout=60.0,
            max_retries=0, http_client=self.http,
        )

    async def aclose(self) -> None:
        await self.oai.close()

    # ---- Muse Spark (chat completions, JSON schema output) ----------------------

    async def _chat(self, system: str, text: str, images: list[str], schema_name: str, cls: type[BaseModel]) -> str:
        self.budget.check()
        content: list[dict] = [{"type": "text", "text": text}]
        content += [{"type": "image_url", "image_url": {"url": _data_url(b)}} for b in images]
        try:
            resp = await self.oai.chat.completions.create(
                model=self.s.muse_model,
                messages=[{"role": "system", "content": system}, {"role": "user", "content": content}],
                response_format={
                    "type": "json_schema",
                    "json_schema": {"name": schema_name, "schema": inline_schema(cls)},
                },
                temperature=0.2,
                max_completion_tokens=self.s.muse_max_completion_tokens,
            )
        except APITimeoutError as exc:
            raise AppError("timeout", "Das Modell hat zu lange gebraucht. Bitte versuche es erneut.", 504) from exc
        except (APIConnectionError, APIStatusError) as exc:
            log.warning("muse call failed: %s", type(exc).__name__)
            raise AppError("upstream_error", "Der Modelldienst ist gerade nicht erreichbar.", 502) from exc
        usage = resp.usage
        tokens_in = usage.prompt_tokens if usage else (len(system) + len(text)) // 4 + 800 * len(images)
        tokens_out = usage.completion_tokens if usage else 800
        self.budget.add(muse_cost(tokens_in, tokens_out))
        if not resp.choices or resp.choices[0].finish_reason == "length":
            raise ModelOutputError("Muse returned no complete choice")
        return resp.choices[0].message.content or ""

    async def _json_call(self, key: str, text: str, images: list[str], cls: type[T]) -> T:
        system = load_prompt(key, self.s.prompts_dir)
        cache_key = ModelCache.key(
            prompt_version(key), self.s.muse_model, system, text, [ModelCache.key(i) for i in images]
        )
        cached = self.cache.get(cache_key)
        if cached is not None:
            try:
                return parse_model_json(cached, cls)
            except AppError:
                pass
        obj, raw = await call_validated(lambda: self._chat(system, text, images, key, cls), cls, retries=1)
        self.cache.set(cache_key, raw)
        return obj

    @staticmethod
    def _images(req: AnalyzeRequest) -> list[str]:
        return [req.image_base64] + [e.image_base64 for e in req.extra_images]

    async def classify(self, req: AnalyzeRequest) -> ClassifyResult:
        text = json.dumps({"user_note": req.note, "locale": req.locale}, ensure_ascii=False)
        return await self._json_call("classify", text, [req.image_base64], ClassifyResult)

    async def diagnose(self, req: AnalyzeRequest, cls: ClassifyResult, segments: list[Segment]) -> DiagnosePlan:
        payload = {
            "category": cls.category,
            "risk_level": cls.risk_level,
            "user_note": req.note,
            "answers": [a.model_dump() for a in req.answers],
            "image_order": ["main"] + [e.purpose for e in req.extra_images],
            "followup_round_already_done": req.is_followup_round,
            "segments": [
                {"id": s.id, "label": s.label, "kind": s.kind, "prompt": s.prompt, "score": s.score, "box": s.box}
                for s in segments
            ],
        }
        return await self._json_call(
            "diagnose", json.dumps(payload, ensure_ascii=False), self._images(req), DiagnosePlan
        )

    async def step_help(self, req: StepHelpRequest) -> StepHelpResponse:
        payload = req.model_dump(exclude={"image_base64"})
        images = [req.image_base64] if req.image_base64 else []
        return await self._json_call("step_help", json.dumps(payload, ensure_ascii=False), images, StepHelpResponse)

    # ---- SAM 3.1 (responses API, one concept per request) -----------------------

    async def segment(self, req: AnalyzeRequest, category: str, prompts: list[str]) -> list[Segment]:
        width, height = Image.open(io.BytesIO(base64.b64decode(req.image_base64))).size
        results = await asyncio.gather(
            *(self._sam_one(req.image_base64, p, width, height) for p in prompts), return_exceptions=True
        )
        dets: list[SamDetection] = []
        errors = [r for r in results if isinstance(r, BaseException)]
        for error in errors:
            if isinstance(error, (BudgetExceeded, asyncio.CancelledError)):
                raise error
        for r in results:
            if not isinstance(r, BaseException):
                dets += r
        if errors and len(errors) == len(results):
            raise errors[0]
        return detections_to_segments(dets)

    async def _sam_stream(self, prompt: str, media: dict) -> str:
        self.budget.check()
        try:
            stream = await self.oai.responses.create(
                model=self.s.sam_model,
                input=[
                    {
                        "type": "message",
                        "role": "user",
                        "content": [
                            {"type": "input_text", "text": prompt},
                            media,
                        ],
                    }
                ],
                metadata={"include_confidence": "true", "mask_encoding": "one_bit"},
                stream=True,
                extra_headers={"Accept": "text/event-stream"},
            )
            parts: list[str] = []
            completed = False
            async with stream:
                async for event in stream:
                    if event.type == "response.output_text.delta":
                        if not isinstance(event.delta, str):
                            raise ModelOutputError("SAM text delta was not a string")
                        parts.append(event.delta)
                    elif event.type == "response.completed":
                        completed = True
                    elif event.type in {"error", "response.failed", "response.incomplete"}:
                        raise ModelOutputError("SAM stream failed or incomplete")
            if not completed:
                raise ModelOutputError("SAM stream ended without response.completed")
        except (APITimeoutError, httpx.TimeoutException) as exc:
            raise AppError("timeout", "Die Segmentierung hat zu lange gebraucht.", 504) from exc
        except (APIError, httpx.HTTPError) as exc:
            log.warning("sam call failed: %s", type(exc).__name__)
            raise AppError("upstream_error", "Der Segmentierungsdienst ist gerade nicht erreichbar.", 502) from exc
        return "".join(parts)

    async def _sam_one(self, image_b64: str, prompt: str, width: int, height: int) -> list[SamDetection]:
        key = ModelCache.key("sam-v2", self.s.sam_model, prompt, ModelCache.key(image_b64))
        text = self.cache.get(key)
        if text is None:
            self.budget.check()
            # SAM's documented examples use PNG; JPEG support is UNBESTÄTIGT.
            png = io.BytesIO()
            with Image.open(io.BytesIO(base64.b64decode(image_b64))) as image:
                image.convert("RGB").save(png, format="PNG")
            image_url = "data:image/png;base64," + base64.b64encode(png.getvalue()).decode("ascii")
            text = await self._sam_stream(prompt, {"type": "input_image", "image_url": image_url})
            self.budget.add(sam_cost(1))  # one image per prompt call
        detections = parse_sam_output(text, prompt, width, height)
        if text.strip() and not detections:
            raise ModelOutputError("SAM returned nonempty text without valid image records")
        self.cache.set(key, text)
        return detections

    async def refine(self, req: RefineRequest) -> Segment:
        image = downscale_b64(req.image_base64)
        with Image.open(io.BytesIO(base64.b64decode(image))) as photo:
            width, height = photo.size
        prompt = geometric_prompt(width, height, req.points, req.box)
        dets = await self._sam_one(image, prompt, width, height)
        # One prompted object (id 1), never silently select another object.
        matches = detections_to_segments([d for d in dets if d.object_id == "1"])
        if not matches:
            raise AppError("no_segment", "Die markierte Stelle konnte nicht erkannt werden. Bitte markiere sie erneut.", 422)
        return matches[0].model_copy(update={"label": req.label, "kind": "damage", "prompt": req.label, "source": "tap"})

    async def ground(self, req: AnalyzeRequest, category: str) -> list[Segment]:
        system = (
            "Locate the visible clothing or shoe damage in the main photo. Return one bounding box "
            "[x1,y1,x2,y2] on the normalized 0-1000 perception grounding grid, origin top left. "
            "Choose the closest damage concept. If no damage is visible, return box=null. Do not invent damage."
        )
        text = json.dumps({"category": category, "user_note": req.note}, ensure_ascii=False)
        key = ModelCache.key("grounding-v1", self.s.muse_model, system, text, ModelCache.key(req.image_base64))
        raw = self.cache.get(key)
        result = None
        if raw is not None:
            try:
                result = parse_model_json(raw, GroundingResult)
            except AppError:
                pass
        if result is None:
            result, raw = await call_validated(
                lambda: self._chat(system, text, [req.image_base64], "grounding", GroundingResult), GroundingResult, retries=1)
            self.cache.set(key, raw)
        if result.box is None:
            return []
        x1, y1, x2, y2 = [max(0.0, min(1.0, v / 1000)) for v in result.box]
        if x2 <= x1 or y2 <= y1:
            raise ModelOutputError("Grounding box has no area")
        with Image.open(io.BytesIO(base64.b64decode(req.image_base64))) as photo:
            width, height = photo.size
        prompt = geometric_prompt(width, height, [], [x1, y1, x2 - x1, y2 - y1])
        dets = await self._sam_one(req.image_base64, prompt, width, height)
        for det in dets:
            det.prompt = result.concept
        # Grounding alone is no mask evidence. Only return the prompted SAM mask.
        return [s.model_copy(update={"source": "grounding"}) for s in detections_to_segments(
            [d for d in dets if d.object_id == "1"]) if s.mask is not None]

    async def track(self, req: TrackRequest) -> TrackResponse:
        video = prepare_video(req.video_base64)
        key = ModelCache.key("sam-video-v1", self.s.sam_model, req.concept, ModelCache.key(video))
        text = self.cache.get(key)
        cached = text is not None
        if text is None:
            text = await self._sam_stream(req.concept, {"type": "input_video", "video_url": f"data:video/mp4;base64,{video}"})
        frames = parse_sam_video(text, req.concept)
        if not cached:
            self.budget.add(sam_video_cost(max((f.index + 1 for f in frames), default=0)))
        if text.strip() and not frames:
            raise ModelOutputError("SAM returned nonempty text without valid video frames")
        self.cache.set(key, text)
        return TrackResponse(frames=frames)

    async def after_preview(self, req: AfterPreviewRequest) -> AfterPreviewResponse:
        image = downscale_b64(req.image_base64)
        prompt = preview_prompt(req)
        key = ModelCache.key("after-preview-v1", self.s.image_model, prompt, ModelCache.key(image))
        cached = self.cache.get(key)
        if cached is not None:
            return AfterPreviewResponse(image_base64=cached, model=self.s.image_model)
        self.budget.check()
        png = io.BytesIO()
        with Image.open(io.BytesIO(base64.b64decode(image))) as photo:
            photo.save(png, format="PNG")
        try:
            result = await self.oai.images.edit(
                model=self.s.image_model, image=("repair.png", png.getvalue(), "image/png"),
                prompt=prompt, n=1, response_format="b64_json",
                # Meta extension (docs/muse-image-notes.md): single pass for a faster preview.
                extra_body={"reasoning_strength": "low"},
            )
        except (APITimeoutError, httpx.TimeoutException) as exc:
            raise AppError("timeout", "Die Vorschau hat zu lange gebraucht. Bitte versuche es erneut.", 504) from exc
        except (APIError, httpx.HTTPError) as exc:
            log.warning("image edit failed: %s", type(exc).__name__)
            raise AppError("upstream_error", "Die Bildvorschau ist gerade nicht erreichbar.", 502) from exc
        self.budget.add(image_cost())
        try:
            output = result.data[0].b64_json if result.data else None
            if not isinstance(output, str) or not output or len(output) > 66_666_668:
                raise ValueError("missing image")
            with Image.open(io.BytesIO(base64.b64decode(output, validate=True))) as edited:
                edited.verify()
        except (ValueError, OSError, AttributeError, TypeError, KeyError, Image.DecompressionBombError) as exc:
            raise ModelOutputError("Image edit returned no valid base64 image") from exc
        self.cache.set(key, output)
        return AfterPreviewResponse(image_base64=output, model=self.s.image_model)

    # ---- Muse Voice Transcribe ----------------------------------------------------

    async def transcribe(self, wav: bytes, duration_s: float) -> str:
        # Revalidate at this boundary too: callers must not bypass the wire contract.
        wav, duration_s = ensure_wav(wav)
        request = {
            "model": self.s.transcribe_model,
            "audioEncoding": "WAV",
            "mode": "PUSH_TO_TALK",
            "languageBias": ["German"],
        }
        key = ModelCache.key("transcribe-v1", self.s.transcribe_model, request, hashlib.sha256(wav).hexdigest())
        cached = self.cache.get(key)
        if cached is not None:
            return cached
        self.budget.check()
        try:
            r = await self.http.post(
                f"{self.s.base_url.rstrip('/')}/asr/transcribe",
                headers={"Authorization": f"Bearer {self.s.meta_api_key}", "Accept": "application/json"},
                files={
                    "request": (None, json.dumps(request), "application/json"),
                    "audio": ("audio.wav", wav, "audio/wav"),
                },
            )
            r.raise_for_status()
        except httpx.TimeoutException as exc:
            raise AppError("timeout", "Die Transkription hat zu lange gebraucht.", 504) from exc
        except httpx.HTTPError as exc:
            log.warning("transcribe failed: %s", type(exc).__name__)
            raise AppError("upstream_error", "Die Transkription ist gerade nicht erreichbar.", 502) from exc
        self.budget.add(transcribe_cost(duration_s))
        try:
            data = r.json()
        except ValueError as exc:
            raise ModelOutputError("ASR returned invalid JSON") from exc
        if not isinstance(data, dict) or not isinstance(data.get("transcript"), str):
            raise ModelOutputError("ASR transcript missing or not a string")
        text = data["transcript"].strip()
        self.cache.set(key, text)
        return text


def build_client(settings: Settings, budget: Budget) -> ModelClient:
    if settings.mock_mode:
        from .mock_client import MockClient

        return MockClient(settings.mock_delay_scale)
    if not settings.meta_api_key:
        raise RuntimeError("MOCK_MODE=0 requires META_API_KEY")
    return RealMetaClient(settings, budget)
