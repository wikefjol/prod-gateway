"""Gateway test fixtures — keys from services/apisix/test-consumers/."""

import json
from pathlib import Path

import httpx
import openai
import pytest

GATEWAY_URL = "http://localhost:9080"
ADMIN_URL = "http://localhost:9180"
API_PREFIX = "/llm/openai"

FIXTURES_DIR = Path(__file__).parent / "fixtures"

# Deterministic dev-only keys (test-consumers/*.json)
BASE_KEY = "test-key-base-1"
PREMIUM_KEY = "test-key-premium-1"


@pytest.fixture()
def gateway_url():
    return GATEWAY_URL


@pytest.fixture()
def admin_url():
    return ADMIN_URL


@pytest.fixture()
def base_client():
    with httpx.Client(
        base_url=GATEWAY_URL,
        headers={"Authorization": f"Bearer {BASE_KEY}"},
        timeout=30,
    ) as client:
        yield client


@pytest.fixture()
def premium_client():
    with httpx.Client(
        base_url=GATEWAY_URL,
        headers={"Authorization": f"Bearer {PREMIUM_KEY}"},
        timeout=30,
    ) as client:
        yield client


@pytest.fixture()
def openai_base_client():
    return openai.OpenAI(
        api_key=BASE_KEY,
        base_url=f"{GATEWAY_URL}{API_PREFIX}/v1",
    )


@pytest.fixture()
def openai_premium_client():
    return openai.OpenAI(
        api_key=PREMIUM_KEY,
        base_url=f"{GATEWAY_URL}{API_PREFIX}/v1",
    )


@pytest.fixture()
def admin_client():
    import os

    admin_key = os.environ.get(
        "ADMIN_KEY", "REDACTED"
    )
    with httpx.Client(
        base_url=ADMIN_URL,
        headers={"X-API-KEY": admin_key},
        timeout=10,
    ) as client:
        yield client


@pytest.fixture()
def load_fixture():
    def _load(name: str) -> dict:
        path = FIXTURES_DIR / name
        if not path.exists():
            pytest.skip(f"fixture {name} not captured yet — run capture/record.py")
        return json.loads(path.read_text())

    return _load
