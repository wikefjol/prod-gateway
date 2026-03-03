# LLM Gateway Test Suite - Technical Overview

**Purpose**: This document describes a comprehensive test suite for validating OpenAI API compatibility and performance of LLM gateway implementations. It may serve as reference for building CI/CD testing infrastructure.

**Repository Context**: Client-side test suite developed to validate gateway behavior against direct provider APIs.

---

## Executive Summary

This test suite implements a **multi-target comparison pattern** that validates gateway implementations maintain API compatibility and acceptable performance characteristics compared to direct provider APIs. It uses a rigorous statistical methodology with N=30 iterations, interleaved ordering, and percentile reporting to produce reliable performance metrics.

### Key Characteristics

- **Language**: Python 3.x with pytest framework
- **Test Scope**: OpenAI SDK compatibility (using official OpenAI Python SDK)
- **Providers Tested**: OpenAI and Anthropic (via OpenAI-compatible endpoints)
- **Test Types**: Functional (API compatibility) + Performance (latency/throughput)
- **Statistical Rigor**: N=30 iterations, interleaved ordering, percentile metrics (p50/p90/p95)

---

## Architecture Overview

### Multi-Target Testing Pattern

The suite tests **5 targets** in parallel:

1. **direct_openai**: Direct OpenAI API calls (baseline for OpenAI models)
2. **direct_anthropic**: Direct Anthropic API via OpenAI compatibility layer (baseline for Anthropic models)
3. **gateway_litellm**: Gateway → LiteLLM → Provider (`/llm/litellm/v1`)
4. **gateway_ai_proxy_openai**: Gateway → ai-proxy → OpenAI (`/llm/ai-proxy/v1` with `gpt-*` models)
5. **gateway_ai_proxy_anthropic**: Gateway → ai-proxy → Anthropic (`/llm/ai-proxy/v1` with `claude-*` models)

### Testing Philosophy

**Baseline Comparison Pattern**:
- Direct provider APIs establish expected behavior (baseline)
- Gateway targets are compared against appropriate baseline
- If baseline passes but gateway fails → incompatibility issue in gateway
- If baseline fails → upstream provider issue or test configuration problem

This pattern ensures we detect gateway-specific issues without false positives from provider-side problems.

---

## Test Categories

### 1. Functional Tests (API Compatibility)

**Location**: `tests/py/openai/chat_completions/`, `tests/py/openai/models/`

**Purpose**: Verify that gateway endpoints return OpenAI-compatible responses

**Coverage**:

#### Positive Cases
- Basic non-streaming chat completions
- Streaming chat completions (Server-Sent Events)
- Model listing (`/v1/models`)
- Response schema validation (structure, not exact values)

#### Negative Cases (Error Handling)
- Missing authentication (401 expected)
- Invalid authentication (401 expected)
- Invalid JSON payloads (400 expected)
- Invalid model names (404 expected)

**Validation Approach**:
- Schema-only validation (checks structure, not exact response content)
- Verifies error responses follow OpenAI format:
  ```json
  {
    "error": {
      "message": "...",
      "type": "...",
      "code": "..."
    }
  }
  ```

**Key Implementation Details**:
```python
# Example test pattern
@pytest.mark.parametrize("target", get_openai_targets())
def test_chat_completions_openai_models__positive(target: Target) -> None:
    # 1. Run baseline test
    baseline = run_positive_case("direct_openai", "openai")
    if not baseline.passed:
        pytest.skip(f"Baseline failed: {baseline.details}")

    # 2. Skip if baseline itself
    if target == "direct_openai":
        assert baseline.passed
        return

    # 3. Test gateway target
    result = run_positive_case(target, "openai")
    assert result.passed, f"{target} failed: {result.details}"
```

### 2. Performance Tests (Latency & Throughput)

**Location**: `tests/py/openai/performance/`

**Purpose**: Quantify performance overhead introduced by gateway layers

**Key Metrics**:

1. **TTFT (Time To First Token)**:
   - Most critical metric from user perspective
   - Measures perceived latency ("waiting time")
   - Time from request sent to first chunk received

2. **Total Response Time**:
   - End-to-end latency
   - Request start to complete response

3. **Token Throughput**:
   - Tokens per second after first token
   - Measures streaming efficiency

**Statistical Methodology**:

The test suite implements rigorous statistical practices to ensure reliable results:

#### Sample Size (N=30)
- Not N=3-5 which is common but unreliable for network calls
- 30 iterations provides stable percentile estimates
- Separate warmup iterations (N=3) to establish connection reuse

#### Interleaved Ordering
Problem: Sequential testing (A×30, then B×30, then C×30) introduces time-drift bias
- Network conditions change over time
- Provider API load varies
- Time-of-day effects

Solution: Rotate target order each iteration
```
Iteration 1: A → B → C
Iteration 2: B → C → A
Iteration 3: C → A → B
...
```

This distributes time-drift effects equally across all targets.

#### Percentile Reporting (p50, p90, p95)
- **p50 (median)**: Typical user experience
- **p90**: 90% of requests are faster than this
- **p95**: Captures tail latency (important for SLAs)

Percentiles are more robust than mean/average because they're not skewed by outliers.

#### Deterministic Output (temperature=0)
- Reduces variance in response length
- More consistent token counts across runs
- Cleaner comparison of pure latency overhead

#### Connection Reuse
- HTTP connections are explicitly reused
- Tests "warm" performance (typical production scenario)
- Not "cold start" performance

#### Error Handling
- 429 rate limits tracked separately (don't contaminate latency metrics)
- Other errors marked as failures
- Success rate reported per target

**Implementation Details**:

```python
# Core measurement function
def measure_streaming_performance(
    client: OpenAI,
    model: str,
    messages: List[dict],
    target_name: str,
    temperature: float = 0.0,
    max_tokens: int = 100,
) -> PerformanceMetrics:
    """
    Measures streaming performance with chunk-level timing.
    Returns metrics including TTFT, total time, token counts.
    """
    start_time = time.time()
    first_chunk_time = None
    chunks_received = 0

    stream = client.chat.completions.create(
        model=model,
        messages=messages,
        stream=True,
        temperature=temperature,
        max_tokens=max_tokens,
    )

    for chunk in stream:
        if first_chunk_time is None:
            first_chunk_time = time.time()
        chunks_received += 1

    end_time = time.time()

    ttft = first_chunk_time - start_time if first_chunk_time else None
    total_time = end_time - start_time

    return PerformanceMetrics(
        target=target_name,
        ttft_seconds=ttft,
        total_seconds=total_time,
        chunks_received=chunks_received,
        # ... more fields
    )

# Aggregation with percentiles
def aggregate_metrics(
    metrics_list: List[PerformanceMetrics]
) -> AggregatedMetrics:
    """Calculate p50, p90, p95 from multiple runs."""
    ttft_values = [m.ttft_seconds for m in metrics_list if m.ttft_seconds]
    total_values = [m.total_seconds for m in metrics_list]

    ttft_percentiles = calculate_percentiles(ttft_values, [50, 90, 95])
    total_percentiles = calculate_percentiles(total_values, [50, 90, 95])

    return AggregatedMetrics(
        ttft_p50=ttft_percentiles[50],
        ttft_p90=ttft_percentiles[90],
        ttft_p95=ttft_percentiles[95],
        total_p50=total_percentiles[50],
        # ... more fields
    )
```

**Test Output Example**:
```
======================================================================
STREAMING PERFORMANCE: OpenAI Models
Configuration: temperature=0.0, interleaved=True
======================================================================
Performance Comparison (baseline: direct_openai)
Model: gpt-4.1-2025-04-14
Sample size: 30 iterations per target

Baseline:
  TTFT: p50=599ms, p90=840ms, p95=862ms
  Total: p50=1.801s, p90=2.425s, p95=2.459s

Target: gateway_litellm
  TTFT: p50=1563ms (+964ms, 2.61x), p90=2637ms, p95=2705ms
  Total: p50=1.926s (+0.124s, 1.07x), p90=2.933s, p95=3.071s

Target: gateway_ai_proxy_openai
  TTFT: p50=615ms (+16ms, 1.03x), p90=957ms, p95=1092ms
  Total: p50=1.848s (+0.047s, 1.03x), p90=2.356s, p95=2.463s

⚠️  WARNING: gateway_litellm TTFT p50 is 2.61x slower than baseline
```

---

## Test Infrastructure

### Configuration Management

**Environment Variables** (`.env` file):
```bash
# Direct provider APIs (baselines)
OPENAI_API_KEY=sk-proj-...
OPENAI_BASE_URL=https://api.openai.com
OPENAI_TEST_MODEL=gpt-4.1-2025-04-14

ANTHROPIC_API_KEY=sk-ant-...
ANTHROPIC_OPENAI_BASE_URL=https://api.anthropic.com/v1/
ANTHROPIC_TEST_MODEL=claude-sonnet-4-5

# Gateway configuration
GATEWAY_HOST=https://lamassu.ita.chalmers.se
GATEWAY_API_KEY=your-gateway-key

# LiteLLM configuration
LITELLM_OPENAI_MODEL=gpt-4.1-2025-04-14
LITELLM_ANTHROPIC_MODEL=claude-sonnet-4-5

# Performance test configuration
PERF_TEST_ITERATIONS=30
PERF_TEST_WARMUP=3
PERF_TEST_INTERLEAVED=true
PERF_TEST_TEMPERATURE=0
PERF_TEST_REUSE_CONNECTIONS=true
```

### Shared Utilities

**`tests/py/openai/test_utils.py`**: Central configuration hub
- Target definitions and routing
- Provider-aware model selection (LiteLLM needs different model names)
- Base URL construction for gateway endpoints

**`tests/py/openai/perf_utils.py`**: Performance measurement library
- `measure_streaming_performance()`: Core timing measurement
- `aggregate_metrics()`: Statistical aggregation
- `calculate_percentiles()`: Linear interpolation for percentiles
- `compare_performance()`: Multi-target comparison

### Test Execution

```bash
# Install dependencies
pip install -r requirements.txt

# Run functional tests (~20-30 seconds)
pytest tests/py/openai/chat_completions/ tests/py/openai/models/ -v

# Run performance tests (~15-20 minutes for N=30)
pytest tests/py/openai/performance/ -v

# Run specific target tests
pytest tests/py/openai/ -v -k "gateway_litellm"
pytest tests/py/openai/ -v -k "gateway_ai_proxy"
```

---

## Results & Findings

### Performance Results (N=30, interleaved)

**OpenAI Models (gpt-4.1-2025-04-14)**:
| Target | TTFT p50 | TTFT Overhead | Total p50 | Assessment |
|--------|----------|---------------|-----------|------------|
| direct_openai (baseline) | 599ms | - | 1.801s | - |
| gateway_ai_proxy_openai | 615ms | +16ms (1.03x) | 1.848s | ✅ Excellent |
| gateway_litellm | 1563ms | +964ms (2.61x) | 1.926s | ⚠️ High TTFT |

**Anthropic Models (claude-sonnet-4-5)**:
| Target | TTFT p50 | TTFT Overhead | Total p50 | Assessment |
|--------|----------|---------------|-----------|------------|
| direct_anthropic (baseline) | 1410ms | - | 3.914s | - |
| gateway_ai_proxy_anthropic | 1547ms | +137ms (1.10x) | 3.830s | ✅ Excellent |
| gateway_litellm | 3818ms | +2408ms (2.71x) | 3.821s | ⚠️ High TTFT |

**Success Rate**: 100% for all targets across 30 iterations

### Key Insights

1. **ai-proxy Performance**: Excellent with 3-10% TTFT overhead
   - APISIX-native routing is very efficient
   - Model name prefix routing (`gpt-*` → OpenAI, `claude-*` → Anthropic)
   - Minimal proxy overhead

2. **LiteLLM Performance**: Functional but significant TTFT overhead (2.6-2.7x)
   - External LiteLLM server adds ~1-2.5 seconds to first token
   - Total response time remains acceptable (7% overhead)
   - Likely due to internal buffering or routing logic
   - Warrants investigation if TTFT is critical

3. **Reliability**: Both gateways achieve 100% success rate
   - No crashes, timeouts, or intermittent failures
   - Consistent behavior across 30 iterations

### Functional Test Results

- **27/29 passing** (2 skipped, 2 known issues)
- **Skipped**: `direct_anthropic` on `/v1/models` endpoint (Anthropic doesn't support this in OpenAI compatibility layer)
- **Known Issues**:
  - ai-proxy returns non-standard error formats for invalid JSON (500) and invalid model (404)
  - These are minor - errors are returned, just not in OpenAI-compatible envelope

---

## Considerations for Gateway CI/CD

### What Could Be Borrowed

#### 1. Multi-Target Comparison Pattern
**Value**: Catches gateway-specific regressions by comparing against baseline
- Prevents false positives from upstream provider issues
- Clear signal when gateway breaks compatibility

**Implementation**: Test fixtures that run same test case against multiple endpoints

#### 2. Statistical Rigor in Performance Testing
**Value**: Reliable performance metrics for SLA monitoring
- N=30 with interleaved ordering eliminates bias
- Percentile reporting captures tail latency (p90/p95 important for SLAs)
- Separate 429 tracking prevents rate limits from skewing metrics

**Implementation**:
- `perf_utils.py` provides reusable measurement functions
- Could be adapted to any HTTP API testing

#### 3. OpenAI SDK Compatibility Testing
**Value**: Gateway claims OpenAI compatibility - tests verify this
- Uses official OpenAI SDK (not custom HTTP clients)
- Tests real-world client usage patterns
- Catches subtle incompatibilities (headers, error formats, streaming)

**Implementation**:
- Parameterized pytest tests with schema validation
- Negative test cases for error handling

#### 4. Warm vs Cold Performance Testing
**Value**: Distinguish between cold-start and steady-state performance
- Warmup iterations establish connection reuse
- Tests realistic production scenarios

### What Might Not Transfer Well

#### 1. Client-Side Perspective
This suite runs **outside** the gateway infrastructure:
- Tests from user's perspective (external network)
- Cannot test internal gateway components directly
- Cannot mock provider responses

**For Gateway CI/CD**: You likely want:
- Internal testing (mock provider responses for speed)
- Component-level tests (APISIX plugins, LiteLLM routing)
- Contract tests with provider API specs

#### 2. Full Provider API Calls
Every test makes real API calls to OpenAI/Anthropic:
- Costs money ($$$ per test run)
- Takes time (15-20 minutes for performance tests)
- Requires valid API keys

**For Gateway CI/CD**: You likely want:
- Mocked provider responses for fast CI feedback
- Real provider tests only in staging/pre-production
- Synthetic test data to avoid API costs

#### 3. Manual Configuration
Uses `.env` files with hardcoded endpoints:
- Not dynamic or auto-discoverable
- Requires manual updates when endpoints change

**For Gateway CI/CD**: You likely want:
- Service discovery or dynamic configuration
- Kubernetes service names or internal DNS
- Config injection via CI/CD variables

#### 4. Limited Endpoint Coverage
Only tests:
- `/v1/chat/completions` (streaming and non-streaming)
- `/v1/models`

**For Gateway CI/CD**: You might want:
- Full OpenAI API coverage (embeddings, audio, vision, etc.)
- Anthropic-native endpoint testing (`/v1/messages`)
- Gateway-specific endpoints (health checks, metrics)

---

## Technical Dependencies

```python
# requirements.txt
pytest==8.0+           # Test framework
openai==1.0+           # Official OpenAI SDK
httpx==0.25+           # HTTP client (used by OpenAI SDK)
python-dotenv==1.0+    # Environment configuration
requests==2.31+        # HTTP library for raw requests
```

**Python Version**: 3.10+ (uses modern type hints)

---

## Code Structure

```
tests/py/openai/
├── test_utils.py              # Target configuration, routing logic
├── perf_utils.py              # Performance measurement utilities
├── chat_completions/
│   └── test_chat_completions_new_layout.py
├── models/
│   └── test_models_new_layout.py
└── performance/
    └── test_perf_streaming.py

.env                           # Configuration (not in git)
requirements.txt               # Python dependencies
CLAUDE.md                      # Developer documentation
PRESTANDATEST_SAMMANFATTNING.md  # Results summary (Swedish)
```

**Total Lines of Code**: ~1500 LOC
- Test utilities: ~400 LOC
- Performance utils: ~300 LOC
- Functional tests: ~500 LOC
- Performance tests: ~300 LOC

---

## Potential Reuse Strategies

### Option A: Extract Performance Measurement Library
**What**: `perf_utils.py` as standalone library
**Use Case**: Add rigorous performance testing to your existing gateway tests
**Effort**: Low - just copy the file and adapt

### Option B: Adopt Multi-Target Pattern
**What**: Baseline comparison testing approach
**Use Case**: Test gateway changes don't break compatibility
**Effort**: Medium - requires adapting target configuration to your infrastructure

### Option C: Reference Implementation
**What**: Use this suite as specification/reference
**Use Case**: Build your own tests with same validation logic
**Effort**: Medium - implement same checks in your preferred testing framework

### Option D: Fork and Adapt
**What**: Clone entire suite and modify for internal use
**Use Case**: Quick start for comprehensive gateway testing
**Effort**: High - need to adapt configuration, add mocking, integrate with CI/CD

---

## Known Limitations

1. **No Mocking**: All tests hit real provider APIs
2. **Limited Anthropic Coverage**: `/v1/models` not supported by Anthropic's OpenAI compatibility layer
3. **OpenAI SDK Only**: Doesn't test native Anthropic SDK usage
4. **No Load Testing**: Tests single-threaded performance, not concurrent load
5. **No Error Injection**: Doesn't test gateway behavior under provider failures
6. **Manual Configuration**: Requires `.env` file updates for new endpoints

---

## Questions for Gateway Team

1. **Do you need client-side validation** (external perspective) or **internal testing** (mock providers)?

2. **Is performance testing infrastructure already in place?** If not, the statistical methodology here (N=30, interleaving, percentiles) could be valuable.

3. **Are you testing OpenAI SDK compatibility specifically?** If yes, the functional tests provide good coverage of edge cases.

4. **What's your CI/CD budget for external API calls?** This suite makes many real API calls (expensive and slow).

5. **Do you have internal SLA targets for TTFT/latency?** The performance tests could be adapted to validate SLAs.

---

## Contact & Questions

This test suite was developed client-side to validate gateway behavior. For questions about implementation details or adaptation for CI/CD, contact the original developer.

**Repository Location**: `/Users/filipberntsson/Dev/tmp_test/`
**Transfer Command**:
```bash
scp TEST_SUITE_OVERVIEW.md filbern@lamassu.ita.chalmers.se:/home/filbern/dev/apisix-gateway/docs/incoming/
```
