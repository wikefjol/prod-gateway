# Alvis vLLM Compatibility Report

> Probed 2026-02-27 from `lamassu.ita.chalmers.se` (129.16.222.8).
> Host: `alvis-worker1.c3se.chalmers.se` — 4× NVIDIA A40.

## Endpoints

| Port  | Model                           | Type      | vLLM    | Health |
|-------|---------------------------------|-----------|---------|--------|
| 43181 | `Qwen/Qwen3-Coder-30B`         | chat      | 0.11.0  | 200    |
| 43111 | `google/gemma-3-12b-it`         | chat      | 0.11.0  | 200    |
| 43121 | `openai/gpt-oss-20b`           | chat      | 0.13.0  | 200    |
| 43211 | `nomic-ai/nomic-embed-text-v1.5`| embedding | 0.11.0  | 200    |

Worker2 (`alvis-worker2.c3se.chalmers.se`): all ports **unreachable** — firewall not yet opened. Email says colleague can set it up on request.

---

## 1. Chat Completions — Non-streaming

All 3 chat ports return standard OpenAI-shaped responses. Key fields present on all:

| Field | Present | Notes |
|-------|---------|-------|
| `id` | yes | `chatcmpl-{hex}` (v0.11) or `chatcmpl-{short-hex}` (v0.13) |
| `object` | yes | `chat.completion` |
| `model` | yes | Matches HuggingFace path exactly |
| `choices[0].message.role` | yes | `assistant` |
| `choices[0].finish_reason` | yes | `stop` or `length` |
| `usage.prompt_tokens` | yes | |
| `usage.completion_tokens` | yes | |
| `usage.total_tokens` | yes | |
| `usage.prompt_tokens_details` | yes | Always `null` |

### Extra fields vs OpenAI

All responses include these additional top-level keys not in standard OpenAI:

- `prompt_logprobs`: `null`
- `prompt_token_ids`: `null`
- `kv_transfer_params`: `null`
- `service_tier`: `null`
- `system_fingerprint`: `null` (OpenAI populates this)

Per-choice extras:

- `stop_reason`: `null` or int (gemma returns `106`)
- `token_ids`: `null`

Per-message extras:

- `refusal`: `null`
- `annotations`: `null`
- `audio`: `null`
- `function_call`: `null`
- `tool_calls`: `[]` (empty array, not absent)
- `reasoning_content`: `null` (or populated for gpt-oss-20b)

### gpt-oss-20b Quirks

This is a **reasoning model**. With `max_tokens: 32`:
- `content` is `null` — all tokens go to reasoning
- `reasoning_content` populated with chain-of-thought
- `finish_reason: "length"` — needs more tokens to produce an answer
- `prompt_tokens: 75` for a 2-word prompt (system prompt baked in?)

---

## 2. Chat Completions — Streaming

All 3 ports produce correct SSE streams.

| Check | Qwen3-Coder-30B | gemma-3-12b-it | gpt-oss-20b |
|-------|-----------------|----------------|-------------|
| `Content-Type` | `text/event-stream; charset=utf-8` | same | same |
| `transfer-encoding` | `chunked` | `chunked` | `chunked` |
| `data: [DONE]` sentinel | yes | yes | yes |
| `id` consistent across chunks | yes | yes | yes |
| `stream_options.include_usage` | works — usage in penultimate chunk | same | same |

### Usage chunk format

Usage arrives in a chunk with `"choices": []` (empty array):
```json
{"id":"chatcmpl-...","object":"chat.completion.chunk","created":...,"model":"...","choices":[],"usage":{"prompt_tokens":14,"total_tokens":17,"completion_tokens":3}}
```

### gpt-oss-20b streaming

Streams `reasoning_content` in delta chunks alongside `reasoning`:
```json
{"delta":{"reasoning":"The","reasoning_content":"The"},...}
```
Both fields contain identical content. `content` delta never appears when reasoning fills the token budget.

---

## 3. Embeddings

Port 43211 — `nomic-ai/nomic-embed-text-v1.5`.

| Check | Single | Batch (3) |
|-------|--------|-----------|
| HTTP status | 200 | 200 |
| `object` | `list` | `list` |
| Dimensions | **768** | 768 each |
| Items returned | 1 | 3 |
| `usage.prompt_tokens` | 4 | 14 |
| `usage.total_tokens` | 4 | 14 |
| `usage.completion_tokens` | 0 | 0 |

Chat completions on embed port returns:
```json
{"error":{"message":"The model does not support Chat Completions API","type":"BadRequestError","code":400}}
```

---

## 4. Auth Behavior

**No API key configured.** vLLM is open — no authentication layer.

| Scenario | HTTP | Result |
|----------|------|--------|
| No auth header | 200 | Normal response |
| `Bearer fake-key-12345` | 200 | Normal response (ignored) |

APISIX must handle all auth — vLLM will accept anything.

---

## 5. Error Behavior

All errors return JSON with `{error: {message, type, param, code}}` — matches OpenAI error shape.

| Scenario | HTTP | `type` | `code` |
|----------|------|--------|--------|
| Wrong model name | 404 | `NotFoundError` | 404 |
| Missing body | 400 | `Bad Request` | 400 |
| Malformed JSON | 400 | `Bad Request` | 400 |
| Missing `messages` | 400 | `Bad Request` | 400 |

Error messages include Python-style validation details (pydantic):
```json
{"message": "[{'type': 'missing', 'loc': ('body', 'messages'), 'msg': 'Field required', ...}]"}
```

---

## 6. Tool/Function Calling

| Model | Support | Notes |
|-------|---------|-------|
| Qwen/Qwen3-Coder-30B | **NO** | `--enable-auto-tool-choice` not set on server |
| google/gemma-3-12b-it | **YES** | Returns `finish_reason: "tool_calls"` + correct `tool_calls` array |
| openai/gpt-oss-20b | **YES** | Same — correct tool call format |

Qwen error:
```json
{"message":"\"auto\" tool choice requires --enable-auto-tool-choice and --tool-call-parser to be set","type":"BadRequestError","code":400}
```

Working tool call response shape:
```json
{
  "finish_reason": "tool_calls",
  "tool_calls": [{
    "id": "chatcmpl-tool-{hex}",
    "type": "function",
    "function": {"name": "get_weather", "arguments": "{\"city\": \"Stockholm\"}"}
  }]
}
```

---

## 7. Capacity Snapshot

All idle at probe time (0 running, 0 waiting, 0% KV cache, 0 preemptions).

| Port | Model | GPU mem util | GPU blocks | Prefix caching |
|------|-------|-------------|------------|----------------|
| 43181 | Qwen3-Coder-30B | 50% | 20,019 | enabled |
| 43111 | gemma-3-12b-it | 15% | 10,952 | enabled |
| 43121 | gpt-oss-20b | 15% | 12,899 | disabled |
| 43211 | nomic-embed-v1.5 | 2% | 1 | disabled |

Prometheus endpoint at `/metrics` — standard vLLM metrics available (`vllm:num_requests_running`, `vllm:kv_cache_usage_perc`, etc.).

---

## 8. Summary — Differences vs Standard OpenAI API

| Aspect | OpenAI API | vLLM (Alvis) | Gateway impact |
|--------|-----------|--------------|----------------|
| **Auth** | Required `Bearer sk-...` | None — open | APISIX handles all auth |
| **Model IDs** | `gpt-4o`, `text-embedding-3-small` | HuggingFace paths | Route config maps our names → HF paths |
| **Streaming usage** | `stream_options` | Supported, same format | Compatible |
| **`[DONE]` sentinel** | `data: [DONE]` | Same | Compatible |
| **Tool calling** | All chat models | Per-model (needs `--enable-auto-tool-choice`) | Qwen3 needs server flag |
| **Embeddings** | `/v1/embeddings` | Same endpoint, same shape | Compatible |
| **Extra response fields** | — | `reasoning_content`, `stop_reason`, `token_ids`, etc. | Strip or pass through |
| **Error format** | `{error:{message,type,code}}` | Same shape, pydantic details in message | Compatible |
| **`system_fingerprint`** | Populated | `null` | Ignore |
| **`tool_calls` default** | Absent when unused | `[]` (empty array) | Handle both |
| **Reasoning models** | `o1`/`o3` use different API | `reasoning_content` in standard chat endpoint | New field to handle |

### Key Takeaways

1. **Drop-in compatible** for basic chat + embeddings — no protocol translation needed
2. **No auth on vLLM** — APISIX is the sole auth/rate-limit layer
3. **gpt-oss-20b is a reasoning model** — needs higher `max_tokens`, returns `reasoning_content` instead of `content` for short limits
4. **Tool calling requires server-side flag** for Qwen3 — request C3SE enable `--enable-auto-tool-choice --tool-call-parser` on port 43181
5. **Worker2 not yet configured** — available on request
6. **Mixed vLLM versions** — 0.11.0 (3 ports) vs 0.13.0 (gpt-oss-20b) — minor response shape differences possible
