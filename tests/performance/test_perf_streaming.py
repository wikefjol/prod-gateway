"""Streaming latency benchmarks — manual runs only, not CI."""

import os
import random

import pytest

from .perf_utils import aggregate, format_report, measure_streaming

N = int(os.environ.get("PERF_ITERATIONS", "30"))
WARMUP = int(os.environ.get("PERF_WARMUP", "3"))
MAX_TOKENS = 100
MESSAGES = [{"role": "user", "content": "Explain what an API gateway is in a few sentences."}]

TARGETS = [
    ("gateway_gpt4o_mini", "gpt-4o-mini"),
    ("gateway_qwen3_coder", "qwen3-coder-30b"),
    ("gateway_gemma3", "gemma-3-12b-it"),
    ("gateway_gpt_oss", "gpt-oss-20b"),
]

VLLM_TARGETS = {"gateway_qwen3_coder", "gateway_gemma3", "gateway_gpt_oss"}


@pytest.mark.perf
@pytest.mark.live
def test_streaming_performance(openai_premium_client):
    """Run streaming benchmarks across all targets, print report."""
    client = openai_premium_client

    # Warmup
    for _ in range(WARMUP):
        for name, model in TARGETS:
            measure_streaming(client, model, MESSAGES, name, MAX_TOKENS)

    # Collect metrics — interleaved to reduce ordering bias
    all_metrics = {name: [] for name, _ in TARGETS}
    for _ in range(N):
        order = list(TARGETS)
        random.shuffle(order)
        for name, model in order:
            m = measure_streaming(client, model, MESSAGES, name, MAX_TOKENS)
            all_metrics[name].append(m)

    # Aggregate and report
    results = {}
    for name, metrics in all_metrics.items():
        agg = aggregate(metrics)
        # Skip target entirely if all iterations failed (backend down)
        if agg.success_count == 0 and name in VLLM_TARGETS:
            print(f"\nSKIPPED {name}: all {N} iterations failed (backend likely down)")
            continue
        results[name] = agg

    report = format_report(results)
    print(f"\n\n{'='*80}")
    print(f"Streaming Performance Report (N={N}, warmup={WARMUP})")
    print(f"{'='*80}")
    print(report)
    print(f"{'='*80}\n")

    # Sanity assertion: at least one successful request per reported target
    for name, agg in results.items():
        assert agg.success_count > 0, f"{name}: zero successful requests"
