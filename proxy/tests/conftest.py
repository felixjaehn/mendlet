import base64
import io

import httpx
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.config import Settings
from app.main import create_app
from app.models import AnalyzeRequest


@pytest.fixture(autouse=True)
def forbid_external_http(monkeypatch):
    """Real-mode tests must inject MockTransport; never consume API credits."""

    async def blocked_async(*args, **kwargs):
        raise AssertionError("External HTTP forbidden in offline tests")

    def blocked_sync(*args, **kwargs):
        raise AssertionError("External HTTP forbidden in offline tests")

    monkeypatch.setattr(httpx.AsyncHTTPTransport, "handle_async_request", blocked_async)
    monkeypatch.setattr(httpx.HTTPTransport, "handle_request", blocked_sync)


def make_image_b64(size=(64, 48), color=(120, 90, 60)) -> str:
    buf = io.BytesIO()
    Image.new("RGB", size, color).save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


@pytest.fixture
def image_b64() -> str:
    return make_image_b64()


@pytest.fixture
def settings(tmp_path) -> Settings:
    return Settings(mock_mode=True, mock_delay_scale=0.0, cache_dir=tmp_path / ".cache", daily_budget_usd=5.0)


@pytest.fixture
def client(settings) -> TestClient:
    return TestClient(create_app(settings))


def make_req(image_b64: str, **kw) -> AnalyzeRequest:
    return AnalyzeRequest(image_base64=image_b64, **kw)
