"""Chat completions error response format tests."""

import pytest


@pytest.mark.smoke
class TestErrorFormats:
    def test_403_openai_format(self, load_fixture):
        f = load_fixture("error_format_403.json")
        assert f["response"]["status"] == 403
        err = f["response"]["body"]["error"]
        assert err["type"] == "invalid_request_error"
        assert err["code"] == "model_not_allowed"
        assert "message" in err

    def test_404_missing_model(self, load_fixture):
        f = load_fixture("error_format_400_no_model.json")
        assert f["response"]["status"] == 404
        assert "error_msg" in f["response"]["body"]

    def test_404_unknown_model(self, load_fixture):
        f = load_fixture("error_format_400_unknown.json")
        assert f["response"]["status"] == 404
        assert "error_msg" in f["response"]["body"]

    def test_404_no_request_id(self, load_fixture):
        """Route-level 404s (pre-plugin) lack x-request-id."""
        f = load_fixture("error_format_400_unknown.json")
        assert "x-request-id" not in f["response"]["headers"]

    def test_403_has_request_id(self, load_fixture):
        """Plugin-level 403s have x-request-id."""
        f = load_fixture("error_format_403.json")
        assert "x-request-id" in f["response"]["headers"]
