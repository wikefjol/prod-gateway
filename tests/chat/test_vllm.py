"""vLLM chat completions tests — model remapping, response shape, reasoning."""

import pytest

from chat.conftest import CHAT_PATH
from conftest import GATEWAY_URL, PREMIUM_KEY

VLLM_CHAT_MODELS = ["qwen3-coder-30b", "gemma-3-12b-it", "gpt-oss-20b"]

HF_NAMES = {
    "qwen3-coder-30b": "Qwen/Qwen3-Coder-30B",
    "gemma-3-12b-it": "google/gemma-3-12b-it",
    "gpt-oss-20b": "openai/gpt-oss-20b",
}


def _chat(model, max_tokens=1):
    import httpx

    return httpx.post(
        f"{GATEWAY_URL}{CHAT_PATH}",
        headers={"Authorization": f"Bearer {PREMIUM_KEY}"},
        json={
            "model": model,
            "messages": [{"role": "user", "content": "hi"}],
            "max_tokens": max_tokens,
        },
        timeout=30,
    )


@pytest.mark.vllm
@pytest.mark.live
@pytest.mark.parametrize("model", VLLM_CHAT_MODELS)
class TestVllmChat:
    def test_vllm_chat_responds(self, model):
        resp = _chat(model)
        assert resp.status_code == 200, f"{model}: got {resp.status_code}"

    def test_vllm_response_shape(self, model):
        body = _chat(model).json()
        assert "choices" in body
        msg = body["choices"][0]["message"]
        assert "content" in msg or "reasoning_content" in msg
        assert body["usage"]["prompt_tokens"] > 0
        assert "model" in body

    def test_vllm_model_remapped(self, model):
        body = _chat(model).json()
        assert body["model"] == HF_NAMES[model], (
            f"expected {HF_NAMES[model]}, got {body['model']}"
        )


@pytest.mark.vllm
@pytest.mark.live
class TestGptOssReasoning:
    def test_gptoss_reasoning_content(self):
        resp = _chat("gpt-oss-20b", max_tokens=32)
        assert resp.status_code == 200
        body = resp.json()
        msg = body["choices"][0]["message"]
        assert msg.get("reasoning_content"), "expected non-empty reasoning_content"
        # content is empty string (not null) at low max_tokens
        assert "content" in msg
