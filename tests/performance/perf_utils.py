"""Performance measurement utilities for streaming latency benchmarks."""

import statistics
import time
from dataclasses import dataclass


@dataclass
class PerformanceMetrics:
    target: str
    ttft_seconds: float | None
    total_seconds: float | None
    chunks_received: int
    error: str | None = None
    rate_limited: bool = False


@dataclass
class AggregatedMetrics:
    ttft_p50: float
    ttft_p90: float
    ttft_p95: float
    total_p50: float
    total_p90: float
    total_p95: float
    success_count: int
    rate_limit_count: int
    total_count: int


def measure_streaming(client, model, messages, target, max_tokens=100):
    """Time a streaming chat completion. Returns PerformanceMetrics."""
    try:
        start = time.perf_counter()
        ttft = None
        chunks = 0

        stream = client.chat.completions.create(
            model=model,
            messages=messages,
            max_tokens=max_tokens,
            temperature=0,
            stream=True,
        )

        for chunk in stream:
            if ttft is None and chunk.choices and chunk.choices[0].delta.content:
                ttft = time.perf_counter() - start
            chunks += 1

        total = time.perf_counter() - start
        return PerformanceMetrics(
            target=target,
            ttft_seconds=ttft,
            total_seconds=total,
            chunks_received=chunks,
        )

    except Exception as e:
        err_str = str(e)
        rate_limited = "429" in err_str or "rate" in err_str.lower()
        return PerformanceMetrics(
            target=target,
            ttft_seconds=None,
            total_seconds=None,
            chunks_received=0,
            error=err_str if not rate_limited else None,
            rate_limited=rate_limited,
        )


def aggregate(metrics_list):
    """Aggregate a list of PerformanceMetrics into percentile summaries."""
    successful = [
        m for m in metrics_list
        if m.error is None and not m.rate_limited and m.ttft_seconds is not None
    ]
    rate_limited = [m for m in metrics_list if m.rate_limited]

    if len(successful) < 2:
        # Need at least 2 data points for quantiles
        ttfts = [m.ttft_seconds for m in successful] if successful else [0.0]
        totals = [m.total_seconds for m in successful] if successful else [0.0]
        val_ttft = ttfts[0]
        val_total = totals[0]
        return AggregatedMetrics(
            ttft_p50=val_ttft, ttft_p90=val_ttft, ttft_p95=val_ttft,
            total_p50=val_total, total_p90=val_total, total_p95=val_total,
            success_count=len(successful),
            rate_limit_count=len(rate_limited),
            total_count=len(metrics_list),
        )

    ttfts = sorted(m.ttft_seconds for m in successful)
    totals = sorted(m.total_seconds for m in successful)

    ttft_q = statistics.quantiles(ttfts, n=20)  # 5% increments
    total_q = statistics.quantiles(totals, n=20)

    return AggregatedMetrics(
        ttft_p50=statistics.median(ttfts),
        ttft_p90=ttft_q[17],   # index 17 = 90th percentile
        ttft_p95=ttft_q[18],   # index 18 = 95th percentile
        total_p50=statistics.median(totals),
        total_p90=total_q[17],
        total_p95=total_q[18],
        success_count=len(successful),
        rate_limit_count=len(rate_limited),
        total_count=len(metrics_list),
    )


def format_report(results):
    """Format aggregated results as a table. results: dict[str, AggregatedMetrics]."""
    lines = []
    w = 11  # column width
    header = (
        f"{'Target':<25}"
        f"{'TTFT p50':>{w}} {'TTFT p90':>{w}} {'TTFT p95':>{w}}"
        f"{'Total p50':>{w}} {'Total p90':>{w}} {'Total p95':>{w}}"
        f"{'OK/Total':>{w}}"
    )
    lines.append(header)
    lines.append("-" * len(header))

    def ms(v):
        return f"{v * 1000:.0f}ms"

    def sec(v):
        return f"{v:.2f}s"

    for name, agg in results.items():
        ok_total = f"{agg.success_count}/{agg.total_count}"
        lines.append(
            f"{name:<25}"
            f"{ms(agg.ttft_p50):>{w}} {ms(agg.ttft_p90):>{w}} {ms(agg.ttft_p95):>{w}}"
            f"{sec(agg.total_p50):>{w}} {sec(agg.total_p90):>{w}} {sec(agg.total_p95):>{w}}"
            f"{ok_total:>{w}}"
        )

    return "\n".join(lines)
