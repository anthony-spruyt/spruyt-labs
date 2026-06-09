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
def fake_custom_callbacks(monkeypatch):
    litellm = types.ModuleType("litellm")
    logging = types.ModuleType("litellm._logging")
    custom_callbacks = types.ModuleType("custom_callbacks")
    middleware_pkg = types.ModuleType("custom_callbacks.middleware")
    pipeline_mod = types.ModuleType("custom_callbacks.middleware.pipeline")
    registry_mod = types.ModuleType("custom_callbacks.middleware.registry")

    class Logger:
        def warning(self, *args, **kwargs):
            pass

    class MiddlewarePipeline:
        def __init__(self, middlewares):
            self.middlewares = middlewares

    sentinel_middlewares = (object(),)
    logging.verbose_proxy_logger = Logger()
    pipeline_mod.MiddlewarePipeline = MiddlewarePipeline
    registry_mod.load_default_middlewares = lambda logger=None: sentinel_middlewares

    monkeypatch.setitem(sys.modules, "litellm", litellm)
    monkeypatch.setitem(sys.modules, "litellm._logging", logging)
    monkeypatch.setitem(sys.modules, "custom_callbacks", custom_callbacks)
    monkeypatch.setitem(sys.modules, "custom_callbacks.middleware", middleware_pkg)
    monkeypatch.setitem(sys.modules, "custom_callbacks.middleware.pipeline", pipeline_mod)
    monkeypatch.setitem(sys.modules, "custom_callbacks.middleware.registry", registry_mod)

    return sentinel_middlewares


def test_pipeline_plugin_exposes_configured_pipeline(fake_custom_callbacks):
    sys.modules.pop("pipeline_plugin", None)

    plugin = importlib.import_module("pipeline_plugin")

    assert plugin.pipeline_middleware.middlewares is fake_custom_callbacks
