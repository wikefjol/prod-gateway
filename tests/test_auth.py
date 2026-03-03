"""Cross-endpoint authentication tests (401 — no key)."""

import pytest


@pytest.mark.smoke
class TestAuth401Smoke:
    def test_chat_no_auth_401(self, load_fixture):
        f = load_fixture("error_format_401.json")
        assert f["response"]["status"] == 401
        body = f["response"]["body"]
        assert "error" in body
        err = body["error"]
        assert err["type"] == "invalid_request_error"
        assert err["code"] == "missing_api_key"
        assert "message" in err

    def test_models_no_auth_401(self, load_fixture):
        f = load_fixture("models_noauth.json")
        assert f["response"]["status"] == 401
        body = f["response"]["body"]
        assert "error" in body
        err = body["error"]
        assert err["type"] == "invalid_request_error"
        assert err["code"] == "missing_api_key"

    def test_401_has_cors(self, load_fixture):
        f = load_fixture("error_format_401.json")
        headers = f["response"]["headers"]
        assert headers.get("access-control-allow-origin") == "*"
        assert "access-control-allow-methods" in headers
        assert "access-control-allow-headers" in headers

    def test_401_has_request_id(self, load_fixture):
        f = load_fixture("error_format_401.json")
        assert "x-request-id" in f["response"]["headers"]
