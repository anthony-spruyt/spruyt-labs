import importlib
import os
import sys
import types

import pytest


_HERE = os.path.dirname(__file__)
_PLUGIN_DIR = os.path.dirname(_HERE)
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)


@pytest.fixture
def registry_module():
    sys.modules.pop("registry", None)
    return importlib.import_module("registry")


class Logger:
    def __init__(self):
        self.warnings = []

    def warning(self, *args, **kwargs):
        self.warnings.append((args, kwargs))


def test_load_middlewares_skips_failed_specs(monkeypatch, registry_module):
    good_module = types.ModuleType("good_module")
    middleware = object()
    good_module.middleware = middleware
    monkeypatch.setitem(sys.modules, "good_module", good_module)

    specs = (
        registry_module.MiddlewareSpec(
            "missing", "missing_module", "middleware", required=False),
        registry_module.MiddlewareSpec("good", "good_module", "middleware"),
    )
    logger = Logger()

    loaded = registry_module.load_middlewares(specs, logger=logger)

    assert loaded == (middleware,)
    assert logger.warnings


def test_load_middlewares_raises_for_failed_required_specs(registry_module):
    specs = (
        registry_module.MiddlewareSpec("missing", "missing_module", "middleware"),
    )

    with pytest.raises(RuntimeError, match="required missing middleware"):
        registry_module.load_middlewares(specs)


def test_secret_masking_is_required(registry_module):
    spec = next(s for s in registry_module.DEFAULT_MIDDLEWARE_SPECS if s.name == "secret-masking")

    assert spec.required


def test_default_specs_point_at_per_middleware_packages(registry_module):
    modules = {s.name: s.module for s in registry_module.DEFAULT_MIDDLEWARE_SPECS}

    assert modules == {
        "secret-masking": "custom_callbacks.middleware.secret_masking.secret_masking",
        "ratelimit-headers": "custom_callbacks.middleware.ratelimit_headers.ratelimit_headers",
    }


def test_ratelimit_headers_is_optional(registry_module):
    spec = next(s for s in registry_module.DEFAULT_MIDDLEWARE_SPECS if s.name == "ratelimit-headers")

    assert not spec.required
