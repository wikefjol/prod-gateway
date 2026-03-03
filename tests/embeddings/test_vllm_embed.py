"""vLLM embeddings tests — nomic-embed-text-v1.5 on Alvis."""

import httpx
import pytest

from conftest import GATEWAY_URL, BASE_KEY, PREMIUM_KEY
from embeddings.conftest import EMBED_PATH

MODEL = "nomic-embed-text-v1.5"


def _embed(key, input_text):
    body = {"model": MODEL, "input": input_text}
    return httpx.post(
        f"{GATEWAY_URL}{EMBED_PATH}",
        headers={"Authorization": f"Bearer {key}"},
        json=body,
        timeout=30,
    )


@pytest.mark.vllm
@pytest.mark.live
class TestEmbedLive:
    def test_embed_responds(self):
        resp = _embed(PREMIUM_KEY, "hello world")
        assert resp.status_code == 200

    def test_embed_vector_dim(self):
        body = _embed(PREMIUM_KEY, "hello world").json()
        vec = body["data"][0]["embedding"]
        assert len(vec) == 768

    def test_embed_object_shape(self):
        body = _embed(PREMIUM_KEY, "hello world").json()
        assert body["object"] == "list"
        entry = body["data"][0]
        assert entry["object"] == "embedding"
        assert "index" in entry

    def test_embed_batch(self):
        body = _embed(PREMIUM_KEY, ["hello", "world"]).json()
        assert len(body["data"]) == 2
        assert body["data"][0]["index"] == 0
        assert body["data"][1]["index"] == 1

    def test_embed_usage(self):
        body = _embed(PREMIUM_KEY, "hello world").json()
        assert body["usage"]["prompt_tokens"] > 0

    def test_embed_no_auth_401(self):
        resp = httpx.post(
            f"{GATEWAY_URL}{EMBED_PATH}",
            json={"model": MODEL, "input": "test"},
            timeout=10,
        )
        assert resp.status_code == 401


@pytest.mark.smoke
class TestEmbedFixture:
    def test_embed_fixture_shape(self, load_fixture):
        f = load_fixture("embeddings/nomic_single.json")
        assert f["response"]["status"] == 200
        body = f["response"]["body"]
        assert body["object"] == "list"
        assert len(body["data"]) > 0
        assert len(body["data"][0]["embedding"]) == 768
