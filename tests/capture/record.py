#!/usr/bin/env python3
"""Capture gateway behavior as JSON fixtures.

Usage: python tests/capture/record.py [--gateway http://localhost:9080]

Probes a live dev gateway and writes fixtures to tests/fixtures/.
Idempotent — safe to re-run.
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import httpx

FIXTURES_DIR = Path(__file__).resolve().parent.parent / "fixtures"

BASE_KEY = "test-key-base-1"
PREMIUM_KEY = "test-key-premium-1"

# All models from MODEL_REGISTRY (model-policy.lua)
ALL_MODELS = [
    "gpt-4o",
    "gpt-4o-mini",
    "gpt-4-turbo",
    "gpt-4",
    "gpt-3.5-turbo-0125",
    "o1",
    "o1-mini",
    "o1-preview",
    "o3-mini",
    "claude-3-haiku-20240307",
    "claude-sonnet-4-20250514",
    "claude-opus-4-20250514",
    "gpt-4.1-2025-04-14",
    "o3-mini-2025-01-31",
    "claude-sonnet-4-5",
    "claude-opus-4-5",
    "claude-haiku-4-5",
    "qwen3-coder-30b",
    "gemma-3-12b-it",
    "gpt-oss-20b",
    "nomic-embed-text-v1.5",
]


def git_revision() -> str:
    try:
        return (
            subprocess.check_output(
                ["git", "rev-parse", "--short", "HEAD"], stderr=subprocess.DEVNULL
            )
            .decode()
            .strip()
        )
    except Exception:
        return "unknown"


def make_fixture(request: dict, response: httpx.Response) -> dict:
    try:
        body = response.json()
    except Exception:
        body = response.text

    return {
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "gateway_revision": git_revision(),
        "request": request,
        "response": {
            "status": response.status_code,
            "headers": dict(response.headers),
            "body": body,
        },
    }


def save(name: str, data: dict) -> None:
    path = FIXTURES_DIR / name
    path.write_text(json.dumps(data, indent=2) + "\n")


def capture_simple(
    client: httpx.Client, name: str, method: str, path: str, **kwargs
) -> dict:
    req_info = {"method": method, "path": path}
    if "json" in kwargs:
        req_info["body"] = kwargs["json"]

    resp = client.request(method, path, **kwargs)
    fixture = make_fixture(req_info, resp)
    save(name, fixture)
    return fixture


def capture_access_matrix(gw_url: str) -> dict:
    """Probe every (tier, model) combo with max_tokens=1."""
    tiers = {"base": BASE_KEY, "premium": PREMIUM_KEY}
    matrix = {}

    for tier, key in tiers.items():
        matrix[tier] = {}
        for model in ALL_MODELS:
            try:
                resp = httpx.post(
                    f"{gw_url}/llm/ai-proxy/v1/chat/completions",
                    headers={"Authorization": f"Bearer {key}"},
                    json={
                        "model": model,
                        "messages": [{"role": "user", "content": "hi"}],
                        "max_tokens": 1,
                    },
                    timeout=30,
                )
                matrix[tier][model] = resp.status_code
            except httpx.TimeoutException:
                matrix[tier][model] = "timeout"
            except Exception as e:
                matrix[tier][model] = f"error:{e}"

    fixture = {
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "gateway_revision": git_revision(),
        "models": ALL_MODELS,
        "tiers": list(tiers.keys()),
        "matrix": matrix,
    }
    (FIXTURES_DIR / "chat").mkdir(parents=True, exist_ok=True)
    save("chat/access_matrix.json", fixture)
    return fixture


def main():
    parser = argparse.ArgumentParser(description="Capture gateway fixtures")
    parser.add_argument("--gateway", default="http://localhost:9080")
    parser.add_argument(
        "--skip-matrix",
        action="store_true",
        help="skip access matrix (hits every model)",
    )
    args = parser.parse_args()

    gw = args.gateway
    admin_url = gw.replace(":9080", ":9180")
    admin_key = os.environ.get(
        "ADMIN_KEY", "205cd2775b5c465657b200516fa4fce5e11487b12e3cb8bb"
    )

    FIXTURES_DIR.mkdir(parents=True, exist_ok=True)

    results = []

    # --- unauthenticated client ---
    noauth = httpx.Client(base_url=gw, timeout=10)

    # --- authenticated clients ---
    base = httpx.Client(
        base_url=gw, headers={"Authorization": f"Bearer {BASE_KEY}"}, timeout=30
    )
    premium = httpx.Client(
        base_url=gw, headers={"Authorization": f"Bearer {PREMIUM_KEY}"}, timeout=30
    )
    admin = httpx.Client(
        base_url=admin_url, headers={"X-API-KEY": admin_key}, timeout=10
    )

    # 1. Health
    print("Capturing health...")
    f = capture_simple(noauth, "health.json", "GET", "/health")
    results.append(("health.json", f["response"]["status"]))

    # 2. Models (base)
    print("Capturing models (base)...")
    f = capture_simple(base, "models_base.json", "GET", "/llm/ai-proxy/v1/models")
    results.append(("models_base.json", f["response"]["status"]))

    # 3. Models (premium)
    print("Capturing models (premium)...")
    f = capture_simple(premium, "models_premium.json", "GET", "/llm/ai-proxy/v1/models")
    results.append(("models_premium.json", f["response"]["status"]))

    # 4. Models (no auth)
    print("Capturing models (no auth)...")
    f = capture_simple(noauth, "models_noauth.json", "GET", "/llm/ai-proxy/v1/models")
    results.append(("models_noauth.json", f["response"]["status"]))

    # 5. Error: 401 (no auth → chat)
    print("Capturing error 401...")
    f = capture_simple(
        noauth,
        "error_format_401.json",
        "POST",
        "/llm/ai-proxy/v1/chat/completions",
        json={
            "model": "gpt-4o-mini",
            "messages": [{"role": "user", "content": "hi"}],
        },
    )
    results.append(("error_format_401.json", f["response"]["status"]))

    # 6. Error: 400 missing model
    print("Capturing error 400 (no model)...")
    f = capture_simple(
        base,
        "error_format_400_no_model.json",
        "POST",
        "/llm/ai-proxy/v1/chat/completions",
        json={"messages": [{"role": "user", "content": "hi"}]},
    )
    results.append(("error_format_400_no_model.json", f["response"]["status"]))

    # 7. Error: 400 unknown model
    print("Capturing error 400 (unknown model)...")
    f = capture_simple(
        base,
        "error_format_400_unknown.json",
        "POST",
        "/llm/ai-proxy/v1/chat/completions",
        json={
            "model": "nonexistent-model-xyz",
            "messages": [{"role": "user", "content": "hi"}],
        },
    )
    results.append(("error_format_400_unknown.json", f["response"]["status"]))

    # 8. Error: 403 (base → premium model)
    print("Capturing error 403...")
    f = capture_simple(
        base,
        "error_format_403.json",
        "POST",
        "/llm/ai-proxy/v1/chat/completions",
        json={
            "model": "gpt-4o",
            "messages": [{"role": "user", "content": "hi"}],
        },
    )
    results.append(("error_format_403.json", f["response"]["status"]))

    # 9. Admin routes
    print("Capturing admin routes...")
    f = capture_simple(admin, "routes_admin.json", "GET", "/apisix/admin/routes")
    results.append(("routes_admin.json", f["response"]["status"]))

    # 10. Embeddings (nomic single input)
    print("Capturing embeddings (nomic single)...")
    (FIXTURES_DIR / "embeddings").mkdir(parents=True, exist_ok=True)
    f = capture_simple(
        premium,
        "embeddings/nomic_single.json",
        "POST",
        "/llm/ai-proxy/v1/embeddings",
        json={"model": "nomic-embed-text-v1.5", "input": "hello world"},
    )
    results.append(("embeddings/nomic_single.json", f["response"]["status"]))

    # 11. Access matrix
    if args.skip_matrix:
        print("Skipping access matrix (--skip-matrix)")
    else:
        print("Capturing access matrix (this may take a minute)...")
        matrix = capture_access_matrix(gw)
        results.append(("access_matrix.json", "done"))

    # Close clients
    noauth.close()
    base.close()
    premium.close()
    admin.close()

    # Summary
    print()
    print(f"{'Fixture':<35} {'Status':>8}")
    print("-" * 45)
    for name, status in results:
        print(f"{name:<35} {status:>8}")
    print(f"\nFixtures saved to {FIXTURES_DIR}/")


if __name__ == "__main__":
    main()
