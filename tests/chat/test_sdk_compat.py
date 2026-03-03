"""OpenAI SDK compatibility tests — non-streaming, streaming, error handling."""

import httpx
import openai
import pytest

from conftest import BASE_KEY, GATEWAY_URL, API_PREFIX

CHAT_URL = f"{GATEWAY_URL}{API_PREFIX}/v1/chat/completions"
MODEL = "gpt-4o-mini"
MESSAGES = [{"role": "user", "content": "Say hello in one word."}]


@pytest.mark.live
class TestNonStreamingSDK:
    def test_basic_completion(self, openai_base_client):
        resp = openai_base_client.chat.completions.create(
            model=MODEL, messages=MESSAGES, max_tokens=5,
        )
        assert isinstance(resp, openai.types.chat.ChatCompletion)
        assert resp.id.startswith("chatcmpl-")
        assert resp.object == "chat.completion"
        assert isinstance(resp.created, int) and resp.created > 0
        assert MODEL in resp.model
        msg = resp.choices[0].message
        assert msg.role == "assistant"
        assert msg.content
        assert resp.choices[0].finish_reason in ("stop", "length")

    def test_usage_present(self, openai_base_client):
        resp = openai_base_client.chat.completions.create(
            model=MODEL, messages=MESSAGES, max_tokens=5,
        )
        assert resp.usage.prompt_tokens > 0
        assert resp.usage.completion_tokens > 0
        assert resp.usage.total_tokens == (
            resp.usage.prompt_tokens + resp.usage.completion_tokens
        )


@pytest.mark.live
class TestStreamingSDK:
    def test_streaming_chunks(self, openai_base_client):
        stream = openai_base_client.chat.completions.create(
            model=MODEL, messages=MESSAGES, max_tokens=20, stream=True,
        )
        chunks = list(stream)
        assert len(chunks) >= 2
        content_parts = []
        for chunk in chunks:
            assert chunk.id.startswith("chatcmpl-")
            assert chunk.object == "chat.completion.chunk"
            if chunk.choices and chunk.choices[0].delta.content:
                content_parts.append(chunk.choices[0].delta.content)
        assert "".join(content_parts), "collected delta content should be non-empty"

    def test_streaming_finish_reason(self, openai_base_client):
        stream = openai_base_client.chat.completions.create(
            model=MODEL, messages=MESSAGES, max_tokens=20, stream=True,
        )
        finish_reasons = []
        for chunk in stream:
            if chunk.choices:
                fr = chunk.choices[0].finish_reason
                if fr is not None:
                    finish_reasons.append(fr)
        assert len(finish_reasons) == 1, "exactly one chunk should have finish_reason"
        assert finish_reasons[0] in ("stop", "length")

    def test_streaming_usage(self, openai_base_client):
        stream = openai_base_client.chat.completions.create(
            model=MODEL, messages=MESSAGES, max_tokens=20, stream=True,
        )
        final_chunk = None
        for chunk in stream:
            final_chunk = chunk
        assert final_chunk.usage is not None, "final chunk should have usage"
        assert final_chunk.usage.prompt_tokens > 0
        assert final_chunk.usage.completion_tokens > 0


@pytest.mark.live
class TestSDKErrorHandling:
    def test_invalid_key_auth_error(self):
        client = openai.OpenAI(
            api_key="invalid-key-xxx",
            base_url=f"{GATEWAY_URL}{API_PREFIX}/v1",
        )
        with pytest.raises(openai.AuthenticationError) as exc_info:
            client.chat.completions.create(
                model=MODEL, messages=MESSAGES, max_tokens=5,
            )
        assert exc_info.value.status_code == 401
        body = exc_info.value.body
        assert isinstance(body.get("type"), str)
        assert isinstance(body.get("message"), str)

    def test_forbidden_model_permission_error(self, openai_base_client):
        with pytest.raises(openai.PermissionDeniedError) as exc_info:
            openai_base_client.chat.completions.create(
                model="gpt-4o", messages=MESSAGES, max_tokens=5,
            )
        assert exc_info.value.status_code == 403
        body = exc_info.value.body
        assert body.get("code") == "model_not_allowed"

    def test_invalid_json_500(self):
        resp = httpx.post(
            CHAT_URL,
            headers={
                "Authorization": f"Bearer {BASE_KEY}",
                "Content-Type": "application/json",
            },
            content=b"{not valid json",
            timeout=30,
        )
        assert resp.status_code == 500
        assert "text/html" in resp.headers.get("content-type", "")
