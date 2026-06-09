import importlib
import os
import sys
import types

import pytest


_HERE = os.path.dirname(__file__)
_PLUGIN_DIR = os.path.dirname(os.path.dirname(_HERE))
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
