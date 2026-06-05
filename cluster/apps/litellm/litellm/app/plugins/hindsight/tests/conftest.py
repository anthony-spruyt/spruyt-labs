"""Shared fixtures for the Hindsight LiteLLM plugin tests.

The plugin module is imported as a top-level ``hindsight_plugin`` module from the
parent directory so the tests are decoupled from the production dotted import
path (``custom_callbacks.hindsight.hindsight_plugin``). The module body is
identical either way.
"""

import importlib
import os
import sys
from types import SimpleNamespace

import httpx
import pytest

_HERE = os.path.dirname(__file__)
_PLUGIN_DIR = os.path.dirname(_HERE)
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)


# ---------------------------------------------------------------------------
# Fake httpx client — records POSTs, returns canned recall/retain responses
# ---------------------------------------------------------------------------
class _FakeResponse:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        return None

    def json(self):
        return self._payload


class _FakeAsyncClient:
    def __init__(self, recorder, init_kwargs):
        self._recorder = recorder
        self._recorder.init_kwargs.append(init_kwargs)

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False

    async def post(self, url, json=None, **kwargs):
        self._recorder.calls.append({"url": url, "json": json})
        if self._recorder.raise_exc is not None:
            raise self._recorder.raise_exc
        if url.endswith("/recall"):
            payload = {"results": [{"id": str(i), "text": t, "type": "fact"}
                                   for i, t in enumerate(self._recorder.recall_texts)]}
        else:
            payload = {"success": True, "operation_id": "op-1"}
        return _FakeResponse(payload)


class HttpxRecorder:
    def __init__(self):
        self.calls = []
        self.init_kwargs = []
        self.recall_texts = []
        self.raise_exc = None

    def factory(self, *args, **kwargs):
        return _FakeAsyncClient(self, kwargs)

    @property
    def recall_calls(self):
        return [c for c in self.calls if c["url"].endswith("/recall")]

    @property
    def retain_calls(self):
        return [c for c in self.calls if c["url"].endswith("/memories")]


@pytest.fixture
def mock_httpx(monkeypatch):
    rec = HttpxRecorder()
    monkeypatch.setattr(httpx, "AsyncClient", rec.factory)
    return rec


# ---------------------------------------------------------------------------
# Plugin module — reloaded fresh per test with a clean env baseline
# ---------------------------------------------------------------------------
@pytest.fixture
def plugin(monkeypatch):
    monkeypatch.setenv("HINDSIGHT_INJECT", "true")
    monkeypatch.setenv("HINDSIGHT_RETAIN", "true")
    monkeypatch.delenv("HINDSIGHT_BASE_URL", raising=False)
    if "hindsight_plugin" in sys.modules:
        mod = importlib.reload(sys.modules["hindsight_plugin"])
    else:
        mod = importlib.import_module("hindsight_plugin")
    return mod


# ---------------------------------------------------------------------------
# Request-shape factories
# ---------------------------------------------------------------------------
@pytest.fixture
def make_anthropic():
    def _make(system=None, user_text="How do I configure Cilium BGP?", headers=None):
        data = {
            "model": "claude-opus-4-8",
            "messages": [{"role": "user", "content": user_text}],
            "proxy_server_request": {"headers": headers or {}},
        }
        if system is not None:
            data["system"] = system
        return data
    return _make


@pytest.fixture
def make_openai():
    def _make(messages=None, user_text="How do I configure Cilium BGP?", headers=None):
        return {
            "model": "gpt-4o",
            "messages": messages if messages is not None
            else [{"role": "user", "content": user_text}],
            "proxy_server_request": {"headers": headers or {}},
        }
    return _make


@pytest.fixture
def make_key():
    def _make(metadata=None):
        return SimpleNamespace(metadata=metadata or {})
    return _make


@pytest.fixture
def make_response():
    """Build a litellm-style response object with assistant text."""
    def _make(text="Use a CiliumBGPPeeringPolicy resource."):
        message = SimpleNamespace(content=text)
        choice = SimpleNamespace(message=message)
        return SimpleNamespace(choices=[choice])
    return _make
