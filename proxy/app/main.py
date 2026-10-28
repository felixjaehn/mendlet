"""FastAPI app: /health, /analyze (SSE or JSON), /step-help, /transcribe."""

import asyncio
import json
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, File, Request, UploadFile
from fastapi.responses import JSONResponse, StreamingResponse

from . import safety
from .audio import MAX_BYTES, ensure_wav
from .budget import Budget
from .clients import ModelClient, build_client
from .config import PROXY_DIR, Settings, load_dotenv
from .errors import AppError
from .images import downscale_b64, prepare_request
from .models import (
    AfterPreviewRequest, AfterPreviewResponse, AnalyzeRequest, AnalyzeResponse, DetectRequest, DetectResponse, RefineRequest,
    Segment, Stage, StepHelpRequest, StepHelpResponse, TrackRequest, TrackResponse,
)
from .pipeline import STAGE_LABELS, analyze

log = logging.getLogger("proxy")


def _sse(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def _error_payload(exc: AppError) -> dict:
    return {"code": exc.code, "message": exc.message}


async def _event_stream(req: AnalyzeRequest, client: ModelClient) -> AsyncIterator[str]:
    queue: asyncio.Queue[tuple[str, dict] | None] = asyncio.Queue()

    async def progress(stage: Stage) -> None:
        await queue.put(("progress", {"stage": stage, "label": STAGE_LABELS[stage]}))

    async def grounding() -> None:
        await queue.put(("grounding", {"label": "Schadstelle genauer lokalisieren"}))

    async def segments_ready(segments: list[Segment]) -> None:
        # Same Segment JSON (and ids) as the final result, so the app can draw masks during diagnose.
        await queue.put(("segments", {"segments": [s.model_dump(mode="json") for s in segments]}))

    async def agent_step(step: dict) -> None:
        await queue.put(("agent_step", step))

    async def runner() -> None:
        try:
            resp = await analyze(req, client, progress, grounding, segments_ready, agent_step)
            await queue.put(("result", resp.model_dump(mode="json")))
        except AppError as exc:
            await queue.put(("error", _error_payload(exc)))
        except Exception as exc:  # noqa: BLE001
            log.error("analyze failed: %s", type(exc).__name__)
            await queue.put(("error", {"code": "internal", "message": "Unerwarteter Fehler. Bitte versuche es erneut."}))
        finally:
            await queue.put(None)

    task = asyncio.create_task(runner())
    try:
        while (item := await queue.get()) is not None:
            yield _sse(*item)
    finally:
        task.cancel()


def create_app(settings: Settings | None = None, client: ModelClient | None = None, budget: Budget | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    budget = budget or Budget(settings.cache_dir / "budget.json", settings.daily_budget_usd)
    client = client or build_client(settings, budget)
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        try:
            yield
        finally:
            close = getattr(client, "aclose", None)
            if close:
                await close()

    app = FastAPI(title="Reparatur-Assistent Proxy", lifespan=lifespan)

    @app.exception_handler(AppError)
    async def _app_error(_: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(status_code=exc.status, content={"error": _error_payload(exc)})

    @app.get("/health")
    async def health() -> dict:
        return {
            "status": "ok",
            "mode": "mock" if settings.mock_mode else "real",
            "agent_mode": settings.agent_mode,
            "spent_today_usd": round(budget.spent_today(), 4),
            "daily_budget_usd": budget.limit_usd,
        }

    @app.post("/analyze", response_model=None)
    async def analyze_endpoint(body: AnalyzeRequest, stream: bool = True):
        budget.check()
        req = prepare_request(body)
        if stream:
            return StreamingResponse(
                _event_stream(req, client),
                media_type="text/event-stream",
                headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
            )
        resp: AnalyzeResponse = await analyze(req, client)
        return resp

    @app.post("/step-help")
    async def step_help(body: StepHelpRequest) -> StepHelpResponse:
        budget.check()
        if body.image_base64:
            body = body.model_copy(update={"image_base64": downscale_b64(body.image_base64)})
        if body.risk_level != "allowed":
            return StepHelpResponse(
                answer="Für diesen Fall gibt es keine Anleitung. Bitte wende dich an einen Fachbetrieb.",
                retry_hint=None, escalate=True,
            )
        out = await client.step_help(body)
        out.escalate = out.escalate or safety.step_help_escalation(body.issue_text, body.risk_level)
        return out

    @app.post("/transcribe")
    async def transcribe(file: UploadFile = File(...)) -> dict:
        budget.check()
        wav, duration = ensure_wav(await file.read(MAX_BYTES + 1))  # bounded; never stored
        return {"text": await client.transcribe(wav, duration)}

    @app.post("/refine")
    async def refine(body: RefineRequest) -> Segment:
        budget.check()
        return await client.refine(body)

    @app.post("/detect")
    async def detect(body: DetectRequest) -> DetectResponse:
        budget.check()
        body = body.model_copy(update={"image_base64": downscale_b64(body.image_base64, 768)})
        return DetectResponse(segments=await client.detect(body))

    @app.post("/track", response_model_exclude_none=True)
    async def track(body: TrackRequest) -> TrackResponse:
        budget.check()
        return await client.track(body)

    @app.post("/after-preview")
    async def after_preview(body: AfterPreviewRequest) -> AfterPreviewResponse:
        budget.check()
        return await client.after_preview(body)

    return app


load_dotenv(PROXY_DIR / ".env")
app = create_app()
