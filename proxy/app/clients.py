"""Model client interface and the real Meta Model API implementation (see docs/api-notes.md)."""

import asyncio
import base64
import io
import json
import logging
from typing import Protocol, TypeVar

import httpx
from openai import APIConnectionError, APIStatusError, APITimeoutError, AsyncOpenAI
from PIL import Image
from pydantic import BaseModel

from .budget import Budget, muse_cost, sam_cost, transcribe_cost
from .cache import ModelCache
from .config import Settings
from .errors import AppError
from .models import (
    AnalyzeRequest,
    ClassifyResult,
    DiagnosePlan,
    Segment,
    StepHelpRequest,
    StepHelpResponse,
)
from .parsing import call_validated, parse_model_json
from .prompts import inline_schema, load_prompt, prompt_version
from .sam import SamDetection, detections_to_segments, parse_sam_output

log = logging.getLogger("proxy.client")
T = TypeVar("T", bound=BaseModel)


class ModelClient(Protocol):
    plan_delay: float  # seconds the pipeline waits in the "plan" stage (mock only)

    async def classify(self, req: AnalyzeRequest) -> ClassifyResult: ...
    async def segment(self, req: AnalyzeRequest, category: str, prompts: list[str]) -> list[Segment]: ...
    async def diagnose(self, req: AnalyzeRequest, cls: ClassifyResult, segments: list[Segment]) -> DiagnosePlan: ...
    async def step_help(self, req: StepHelpRequest) -> StepHelpResponse: ...
    async def transcribe(self, wav: bytes, duration_s: float) -> str: ...


def _data_url(b64: str) -> str:
    return f"data:image/jpeg;base64,{b64}"


class RealMetaClient:
    plan_delay = 0.0

    def __init__(self, settings: Settings, budget: Budget) -> None:
        self.s = settings
        self.budget = budget
        self.cache = ModelCache(settings.cache_dir, settings.cache_model_calls)
        self.oai = AsyncOpenAI(api_key=settings.meta_api_key, base_url=settings.base_url, timeout=60.0)

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
        for r in results:
            if not isinstance(r, BaseException):
                dets += r
        if errors and len(errors) == len(results):
            raise errors[0]
        return detections_to_segments(dets)

    async def _sam_one(self, image_b64: str, prompt: str, width: int, height: int) -> list[SamDetection]:
        key = ModelCache.key("sam", self.s.sam_model, prompt, ModelCache.key(image_b64))
        text = self.cache.get(key)
        if text is None:
            self.budget.check()
            try:
                resp = await self.oai.responses.create(
                    model=self.s.sam_model,
                    input=[
                        {
                            "type": "message",
                            "role": "user",
                            "content": [
                                {"type": "input_text", "text": prompt},
                                {"type": "input_image", "image_url": _data_url(image_b64)},
                            ],
                        }
                    ],
                    metadata={"include_confidence": "true"},
                )
            except APITimeoutError as exc:
                raise AppError("timeout", "Die Segmentierung hat zu lange gebraucht.", 504) from exc
            except (APIConnectionError, APIStatusError) as exc:
                log.warning("sam call failed: %s", type(exc).__name__)
                raise AppError("upstream_error", "Der Segmentierungsdienst ist gerade nicht erreichbar.", 502) from exc
            self.budget.add(sam_cost(1))  # one image per prompt call
            text = resp.output_text or ""
            self.cache.set(key, text)
        return parse_sam_output(text, prompt, width, height)

    # ---- Muse Voice Transcribe ----------------------------------------------------

    async def transcribe(self, wav: bytes, duration_s: float) -> str:
        self.budget.check()
        request = {
            "model": self.s.transcribe_model,
            "audioEncoding": "WAV",
            "mode": "PUSH_TO_TALK",
            "languageBias": ["German"],
        }
        try:
            async with httpx.AsyncClient(timeout=60.0) as http:
                r = await http.post(
                    f"{self.s.base_url}/asr/transcribe",
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
        return str(r.json().get("transcript", "")).strip()


def build_client(settings: Settings, budget: Budget) -> ModelClient:
    if settings.mock_mode:
        from .mock_client import MockClient

        return MockClient(settings.mock_delay_scale)
    if not settings.meta_api_key:
        raise RuntimeError("MOCK_MODE=0 requires META_API_KEY")
    return RealMetaClient(settings, budget)
