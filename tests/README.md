# Gateway Test Suite

Black-box characterization tests against the running gateway. See [ADR 007](../docs/adr/007-black-box-testing.md) for strategy.

## Setup
```bash
python -m venv tests/.venv
tests/.venv/bin/pip install -r tests/requirements.txt
```

## Running Tests
```bash
# All tests
tests/.venv/bin/pytest tests/

# By marker
tests/.venv/bin/pytest tests/ -m smoke      # fast, no network
tests/.venv/bin/pytest tests/ -m live        # requires running gateway
tests/.venv/bin/pytest tests/ -m vllm        # requires Alvis vLLM backends
tests/.venv/bin/pytest tests/ -m perf -v -s  # streaming latency benchmarks (manual)

# Performance with custom iterations
PERF_ITERATIONS=3 PERF_WARMUP=1 tests/.venv/bin/pytest tests/performance/ -v -s
```

## Structure
```
tests/
├── conftest.py          # shared fixtures: base_client, premium_client, openai_*_client, admin_client, load_fixture
├── pytest.ini           # markers: smoke, live, vllm, perf
├── requirements.txt     # httpx, pytest, pytest-asyncio, openai
├── fixtures/            # JSON snapshots from capture/record.py
├── capture/record.py    # probe live gateway → save fixtures (idempotent)
├── performance/         # streaming latency benchmarks (TTFT + total, percentiles)
├── chat/                # chat completions: access control, vLLM, OpenAI SDK compat
├── embeddings/          # vLLM embeddings endpoint
├── test_auth.py         # 401 / CORS smoke tests
└── test_health.py       # health endpoint + revision header
```

## Keys
Deterministic dev-only keys from `services/apisix/test-consumers/`:
- `test-key-base-1` (base tier)
- `test-key-premium-1` (premium tier)

## Important
- API routes are `/llm/ai-proxy/v1/...`, NOT `/v1/...`
- Capture fixtures: `tests/.venv/bin/python tests/capture/record.py`
- Revision check: `curl -sI http://localhost:9080/health | grep X-Gateway-Revision` should match `git rev-parse --short HEAD`
