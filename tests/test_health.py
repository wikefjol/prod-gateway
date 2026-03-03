"""Gateway health endpoint tests."""

import subprocess

import httpx
import pytest

from conftest import GATEWAY_URL


@pytest.mark.smoke
class TestHealthSmoke:
    def test_health_status(self, load_fixture):
        f = load_fixture("health.json")
        assert f["response"]["status"] == 200
        assert f["response"]["body"] == {"status": "healthy"}

    def test_health_has_revision_header(self, load_fixture):
        f = load_fixture("health.json")
        assert "x-gateway-revision" in f["response"]["headers"]


@pytest.mark.live
class TestHealthLive:
    def test_health_live(self):
        resp = httpx.get(f"{GATEWAY_URL}/health", timeout=5)
        assert resp.status_code == 200
        assert resp.json() == {"status": "healthy"}

    def test_revision_matches_git(self):
        resp = httpx.get(f"{GATEWAY_URL}/health", timeout=5)
        rev = resp.headers.get("x-gateway-revision")
        assert rev, "x-gateway-revision header missing"
        git_rev = (
            subprocess.check_output(
                ["git", "rev-parse", "--short", "HEAD"], stderr=subprocess.DEVNULL
            )
            .decode()
            .strip()
        )
        assert rev == git_rev, f"gateway revision {rev!r} != git {git_rev!r}"
