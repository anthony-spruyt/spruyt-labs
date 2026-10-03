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


_CHATGPT_DISABLED = pytest.mark.skip(
    reason="chatgpt middleware not in registry.DEFAULT_MIDDLEWARE_SPECS")


def test_production_dotted_imports_resolve(production_import_shape):
    modules = [
        "custom_callbacks.middleware.hindsight.hindsight",
        "custom_callbacks.middleware.pipeline",
        "custom_callbacks.middleware.registry",
        "custom_callbacks.middleware.pipeline_plugin",
        "custom_callbacks.middleware.secret_masking.shared_fakes",
        "custom_callbacks.middleware.secret_masking.secret_masking",
        "custom_callbacks.middleware.ratelimit_headers.ratelimit_headers",
        "custom_callbacks.middleware.mcp_tool_routing.mcp_tool_routing",
        "custom_callbacks.middleware.chatgpt.chatgpt",
    ]

    for module in modules:
        sys.modules.pop(module, None)

    for module in modules:
        importlib.import_module(module)


def test_production_pipeline_loads_secret_masking(production_import_shape):
    for module in [
        "custom_callbacks.middleware.secret_masking.secret_masking",
        "custom_callbacks.middleware.registry",
        "custom_callbacks.middleware.pipeline_plugin",
    ]:
        sys.modules.pop(module, None)

    plugin = importlib.import_module("custom_callbacks.middleware.pipeline_plugin")
    masking = importlib.import_module("custom_callbacks.middleware.secret_masking.secret_masking")

    assert masking.secret_masking in plugin.pipeline_middleware.middlewares


def test_production_pipeline_loads_ratelimit_headers(production_import_shape):
    for module in [
        "custom_callbacks.middleware.ratelimit_headers.ratelimit_headers",
        "custom_callbacks.middleware.registry",
        "custom_callbacks.middleware.pipeline_plugin",
    ]:
        sys.modules.pop(module, None)

    plugin = importlib.import_module("custom_callbacks.middleware.pipeline_plugin")
    restorer = importlib.import_module("custom_callbacks.middleware.ratelimit_headers.ratelimit_headers")

    assert restorer.ratelimit_headers in plugin.pipeline_middleware.middlewares


def test_production_pipeline_loads_mcp_tool_routing(production_import_shape):
    for module in [
        "custom_callbacks.middleware.mcp_tool_routing.mcp_tool_routing",
        "custom_callbacks.middleware.registry",
        "custom_callbacks.middleware.pipeline_plugin",
    ]:
        sys.modules.pop(module, None)

    plugin = importlib.import_module("custom_callbacks.middleware.pipeline_plugin")
    routing = importlib.import_module("custom_callbacks.middleware.mcp_tool_routing.mcp_tool_routing")

    assert routing.mcp_tool_routing in plugin.pipeline_middleware.middlewares


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


@_CHATGPT_DISABLED
async def test_production_pipeline_runs_hindsight_then_chatgpt(
    monkeypatch, production_import_shape,
):
    for module in [
        "custom_callbacks.middleware.chatgpt.chatgpt",
        "custom_callbacks.middleware.hindsight.hindsight",
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
