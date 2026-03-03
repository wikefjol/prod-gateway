"""Chat completions access control matrix tests."""

import json
from pathlib import Path

import httpx
import pytest

from chat.conftest import BASE_ALLOWED, CHAT_PATH
from conftest import BASE_KEY, GATEWAY_URL, PREMIUM_KEY

FIXTURES_DIR = Path(__file__).resolve().parent.parent / "fixtures"


def _load_matrix():
    path = FIXTURES_DIR / "chat" / "access_matrix.json"
    if not path.exists():
        return []
    data = json.loads(path.read_text())
    params = []
    for tier in data["tiers"]:
        for model in data["models"]:
            status = data["matrix"][tier][model]
            params.append((tier, model, status))
    return params


MATRIX = _load_matrix()

# Models with known xfail — routes missing for premium tier
XFAIL_PREMIUM = {"o1-mini", "o1-preview"}


@pytest.mark.smoke
@pytest.mark.parametrize("tier,model,status", MATRIX, ids=[f"{t}-{m}" for t, m, _ in MATRIX])
class TestAccessMatrixSmoke:
    def test_access_matrix_rules(self, tier, model, status):
        if model == "nomic-embed-text-v1.5":
            assert status == 404, "embeddings-only model should 404 on chat"
            return

        if tier == "base":
            if model in BASE_ALLOWED:
                assert status == 200, f"base should access {model}"
            else:
                assert status == 403, f"base should be denied {model}"

        elif tier == "premium":
            if model in XFAIL_PREMIUM:
                pytest.xfail(f"{model}: missing premium route (404 instead of 200/400)")
            assert status != 403, f"premium should never get 403 for {model}"
            assert status in (200, 400, 404), f"unexpected status {status} for premium/{model}"


@pytest.mark.live
@pytest.mark.parametrize("tier,model,status", MATRIX, ids=[f"{t}-{m}" for t, m, _ in MATRIX])
class TestAccessMatrixLive:
    def test_access_matrix_live(self, tier, model, status):
        key = BASE_KEY if tier == "base" else PREMIUM_KEY
        resp = httpx.post(
            f"{GATEWAY_URL}{CHAT_PATH}",
            headers={"Authorization": f"Bearer {key}"},
            json={
                "model": model,
                "messages": [{"role": "user", "content": "hi"}],
                "max_tokens": 1,
            },
            timeout=30,
        )
        assert resp.status_code == status, (
            f"{tier}/{model}: expected {status}, got {resp.status_code}"
        )
