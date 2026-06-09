import importlib
import os
import sys
import types

import pytest


_HERE = os.path.dirname(__file__)
_PLUGIN_DIR = os.path.dirname(_HERE)
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)


@pytest.fixture(autouse=True)
def fake_litellm(monkeypatch):
    litellm = types.ModuleType("litellm")
    integrations = types.ModuleType("litellm.integrations")
    custom_logger = types.ModuleType("litellm.integrations.custom_logger")
    logging = types.ModuleType("litellm._logging")

    class CustomLogger:
        pass

    class Logger:
        def __init__(self):
            self.warnings = []

        def warning(self, *args, **kwargs):
            self.warnings.append((args, kwargs))

    custom_logger.CustomLogger = CustomLogger
    logging.verbose_proxy_logger = Logger()
    monkeypatch.setitem(sys.modules, "litellm", litellm)
    monkeypatch.setitem(sys.modules, "litellm.integrations", integrations)
    monkeypatch.setitem(sys.modules, "litellm.integrations.custom_logger", custom_logger)
    monkeypatch.setitem(sys.modules, "litellm._logging", logging)
    return logging


@pytest.fixture
def pipeline_module():
    sys.modules.pop("pipeline", None)
    return importlib.import_module("pipeline")


class AddSystemMiddleware:
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        data["system"] = "system from first middleware"
        return data


class SystemToDeveloperMiddleware:
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        system = data.pop("system", None)
        if system:
            data.setdefault("messages", []).insert(
                0, {"role": "developer", "content": system})
        return data


class FailingPreCallMiddleware:
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        raise RuntimeError("boom")


class RejectingPreCallMiddleware:
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        return "blocked by guardrail"


class SuccessRecorderMiddleware:
    def __init__(self):
        self.called = False

    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        self.called = True


class FailingSuccessMiddleware:
    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        raise RuntimeError("retain failed")


async def test_pre_call_pipeline_preserves_declared_order(pipeline_module):
    pipeline = pipeline_module.MiddlewarePipeline((
        AddSystemMiddleware(),
        SystemToDeveloperMiddleware(),
    ))
    data = {"model": "chatgpt/gpt-5.5", "messages": []}

    out = await pipeline.async_pre_call_hook(None, None, data, "anthropic_messages")

    assert "system" not in out
    assert out["messages"][0] == {
        "role": "developer",
        "content": "system from first middleware",
    }


async def test_pre_call_fail_open_continues_to_next_middleware(pipeline_module):
    pipeline = pipeline_module.MiddlewarePipeline((
        FailingPreCallMiddleware(),
        AddSystemMiddleware(),
    ))
    data = {"messages": []}

    out = await pipeline.async_pre_call_hook(None, None, data, "completion")

    assert out["system"] == "system from first middleware"


async def test_pre_call_can_fail_closed(pipeline_module):
    pipeline = pipeline_module.MiddlewarePipeline((FailingPreCallMiddleware(),), fail_open=False)

    with pytest.raises(RuntimeError, match="boom"):
        await pipeline.async_pre_call_hook(None, None, {"messages": []}, "completion")


async def test_pre_call_string_rejection_short_circuits(pipeline_module):
    pipeline = pipeline_module.MiddlewarePipeline((
        RejectingPreCallMiddleware(),
        AddSystemMiddleware(),
    ))

    out = await pipeline.async_pre_call_hook(None, None, {"messages": []}, "completion")

    assert out == "blocked by guardrail"


async def test_success_hooks_are_delegated(pipeline_module):
    recorder = SuccessRecorderMiddleware()
    pipeline = pipeline_module.MiddlewarePipeline((recorder,))

    await pipeline.async_log_success_event({}, {}, 0.0, 1.0)

    assert recorder.called is True


async def test_success_hook_fail_open_does_not_skip_following_hooks(pipeline_module):
    recorder = SuccessRecorderMiddleware()
    pipeline = pipeline_module.MiddlewarePipeline((FailingSuccessMiddleware(), recorder))

    await pipeline.async_log_success_event({}, {}, 0.0, 1.0)

    assert recorder.called is True
