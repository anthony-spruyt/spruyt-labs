import importlib
import os
import sys
import types

import httpx
import pytest


_HERE = os.path.dirname(__file__)
_MIDDLEWARE_DIR = os.path.dirname(_HERE)
_PLUGINS_DIR = os.path.dirname(_MIDDLEWARE_DIR)


@pytest.fixture
def production_import_shape(monkeypatch):
    litellm = types.ModuleType("litellm")
    integrations = types.ModuleType("litellm.integrations")
    custom_logger = types.ModuleType("litellm.integrations.custom_logger")
    logging = types.ModuleType("litellm._logging")

    class CustomLogger:
        pass

    class Logger:
        def debug(self, *args, **kwargs):
            pass

        def warning(self, *args, **kwargs):
            pass

    custom_logger.CustomLogger = CustomLogger
    logging.verbose_proxy_logger = Logger()

    custom_callbacks = types.ModuleType("custom_callbacks")
    custom_callbacks.__path__ = [_PLUGINS_DIR]

    monkeypatch.setitem(sys.modules, "litellm", litellm)
    monkeypatch.setitem(sys.modules, "litellm.integrations", integrations)
    monkeypatch.setitem(sys.modules, "litellm.integrations.custom_logger", custom_logger)
    monkeypatch.setitem(sys.modules, "litellm._logging", logging)
    monkeypatch.setitem(sys.modules, "custom_callbacks", custom_callbacks)


def test_production_dotted_imports_resolve(production_import_shape):
    modules = [
        "custom_callbacks.chatgpt.chatgpt_plugin",
        "custom_callbacks.hindsight.hindsight_plugin",
        "custom_callbacks.middleware.pipeline",
        "custom_callbacks.middleware.registry",
        "custom_callbacks.middleware.pipeline_plugin",
    ]

    for module in modules:
        sys.modules.pop(module, None)

    plugin = importlib.import_module("custom_callbacks.middleware.pipeline_plugin")

    assert plugin.pipeline_middleware.middlewares
    assert len(plugin.pipeline_middleware.middlewares) == 2


class _FakeResponse:
    def raise_for_status(self):
        return None

    def json(self):
        return {"results": [{"text": "remembered fact"}]}


class _FakeAsyncClient:
    def __init__(self, *args, **kwargs):
        pass

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False

    async def post(self, url, json=None, **kwargs):
        return _FakeResponse()


async def test_production_pipeline_runs_hindsight_then_chatgpt(
    monkeypatch, production_import_shape,
):
    for module in [
        "custom_callbacks.chatgpt.chatgpt_plugin",
        "custom_callbacks.hindsight.hindsight_plugin",
        "custom_callbacks.middleware.pipeline",
        "custom_callbacks.middleware.registry",
        "custom_callbacks.middleware.pipeline_plugin",
    ]:
        sys.modules.pop(module, None)
    monkeypatch.setattr(httpx, "AsyncClient", _FakeAsyncClient)

    plugin = importlib.import_module("custom_callbacks.middleware.pipeline_plugin")
    data = {
        "model": "chatgpt/gpt-5.5",
        "system": "original system",
        "messages": [{"role": "user", "content": "hello"}],
        "proxy_server_request": {"headers": {"x-hindsight-bank": "repo"}},
    }

    out = await plugin.pipeline_middleware.async_pre_call_hook(
        None, None, data, "anthropic_messages")

    assert "system" not in out
    assert out["messages"][0]["role"] == "developer"
    assert "original system" in out["messages"][0]["content"]
    assert "remembered fact" in out["messages"][0]["content"]
