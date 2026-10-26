import base64
import io

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.budget import Budget
from app.config import Settings
from app.main import create_app
from app.models import AnalyzeRequest


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
