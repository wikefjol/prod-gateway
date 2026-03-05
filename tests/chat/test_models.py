"""Model listing endpoint tests (/v1/models)."""

import pytest

from chat.conftest import BASE_ALLOWED


@pytest.mark.smoke
class TestModelsSmoke:
    def test_models_base_count(self, load_fixture):
        f = load_fixture("models_base.json")
        models = f["response"]["body"]["data"]
        assert len(models) == len(BASE_ALLOWED)

    def test_models_base_ids(self, load_fixture):
        f = load_fixture("models_base.json")
        ids = {m["id"] for m in f["response"]["body"]["data"]}
        expected = BASE_ALLOWED
        assert ids == expected

    def test_models_base_object_shape(self, load_fixture):
        f = load_fixture("models_base.json")
        for m in f["response"]["body"]["data"]:
            assert "id" in m
            assert m["object"] == "model"
            assert "created" in m
            assert "owned_by" in m

    def test_models_premium_count(self, load_fixture):
        f = load_fixture("models_premium.json")
        models = f["response"]["body"]["data"]
        assert len(models) == 21

    def test_models_premium_superset(self, load_fixture):
        base = load_fixture("models_base.json")
        premium = load_fixture("models_premium.json")
        base_ids = {m["id"] for m in base["response"]["body"]["data"]}
        premium_ids = {m["id"] for m in premium["response"]["body"]["data"]}
        assert premium_ids >= base_ids, f"missing from premium: {base_ids - premium_ids}"
