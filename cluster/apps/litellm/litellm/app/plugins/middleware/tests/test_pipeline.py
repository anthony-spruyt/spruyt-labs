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


class SuffixResponseMiddleware:
    def __init__(self, suffix):
        self.suffix = suffix

    async def async_post_call_success_hook(self, data, user_api_key_dict, response):
        return response + self.suffix


class NoOpResponseMiddleware:
    async def async_post_call_success_hook(self, data, user_api_key_dict, response):
        return None


class FailingResponseMiddleware:
    async def async_post_call_success_hook(self, data, user_api_key_dict, response):
        raise RuntimeError("boom")


class UpperStreamMiddleware:
    async def async_post_call_streaming_iterator_hook(self, user_api_key_dict, response, request_data):
        async for chunk in response:
            yield chunk.upper()


class SuffixStreamMiddleware:
    async def async_post_call_streaming_iterator_hook(self, user_api_key_dict, response, request_data):
        async for chunk in response:
            yield chunk + request_data["suffix"]


class FailingStreamMiddleware:
    def async_post_call_streaming_iterator_hook(self, user_api_key_dict, response, request_data):
        raise RuntimeError("boom")


async def _stream(items):
    for item in items:
        yield item


async def test_post_call_success_hooks_chain_in_order(pipeline_module):
    pipeline = pipeline_module.MiddlewarePipeline((
        SuffixResponseMiddleware("-a"),
        NoOpResponseMiddleware(),
        FailingResponseMiddleware(),
        SuffixResponseMiddleware("-b"),
    ))

    out = await pipeline.async_post_call_success_hook({}, None, "resp")

    assert out == "resp-a-b"


async def test_post_call_success_hook_without_middlewares_returns_response(pipeline_module):
    pipeline = pipeline_module.MiddlewarePipeline(())

    assert await pipeline.async_post_call_success_hook({}, None, "resp") == "resp"


async def test_streaming_iterator_hooks_chain_in_order(pipeline_module):
    pipeline = pipeline_module.MiddlewarePipeline((
        UpperStreamMiddleware(),
        FailingStreamMiddleware(),
        SuffixStreamMiddleware(),
    ))

    out = [c async for c in pipeline.async_post_call_streaming_iterator_hook(
        None, _stream(["a", "b"]), {"suffix": "!"})]

    assert out == ["A!", "B!"]


async def test_streaming_iterator_without_middlewares_passes_through(pipeline_module):
    pipeline = pipeline_module.MiddlewarePipeline(())
    items = [object(), object()]

    out = [c async for c in pipeline.async_post_call_streaming_iterator_hook(
        None, _stream(items), {})]

    assert out == items


class FailureRecorderMiddleware:
    def __init__(self):
        self.seen = None

    async def async_post_call_failure_hook(self, request_data, original_exception, user_api_key_dict, traceback_str=None):
        self.seen = request_data


class FailingFailureMiddleware:
    async def async_post_call_failure_hook(self, request_data, original_exception, user_api_key_dict, traceback_str=None):
        raise RuntimeError("boom")


async def test_post_call_failure_hooks_are_delegated(pipeline_module):
    recorder = FailureRecorderMiddleware()
    pipeline = pipeline_module.MiddlewarePipeline((FailingFailureMiddleware(), recorder))

    await pipeline.async_post_call_failure_hook({"id": 1}, RuntimeError("x"), None)

    assert recorder.seen == {"id": 1}


class TransformingFailureMiddleware:
    def __init__(self, replacement):
        self.replacement = replacement

    async def async_post_call_failure_hook(self, request_data, original_exception, user_api_key_dict, traceback_str=None):
        return self.replacement


async def test_post_call_failure_hook_returns_first_transformed_error_and_runs_all_hooks(pipeline_module):
    first, second = RuntimeError("first"), RuntimeError("second")
    recorder = FailureRecorderMiddleware()
    pipeline = pipeline_module.MiddlewarePipeline((
        FailingFailureMiddleware(),
        FailureRecorderMiddleware(),
        TransformingFailureMiddleware(first),
        TransformingFailureMiddleware(second),
        recorder,
    ))

    out = await pipeline.async_post_call_failure_hook({"id": 1}, RuntimeError("x"), None)

    assert out is first
    assert recorder.seen == {"id": 1}


async def test_fail_open_warnings_log_exception_type_not_message(pipeline_module, fake_litellm):
    pipeline = pipeline_module.MiddlewarePipeline((FailingResponseMiddleware(),))

    await pipeline.async_post_call_success_hook({}, None, "resp")

    args = fake_litellm.verbose_proxy_logger.warnings[-1][0]
    assert "RuntimeError" in args
    assert all("boom" not in str(a) for a in args)


class MidStreamFailingMiddleware:
    async def async_post_call_streaming_iterator_hook(self, user_api_key_dict, response, request_data):
        buffered = []
        async for chunk in response:
            if chunk == "b":
                raise RuntimeError("boom")
            buffered.append(chunk.upper())
        for chunk in buffered:
            yield chunk


class PassThroughStreamMiddleware:
    async def async_post_call_streaming_iterator_hook(self, user_api_key_dict, response, request_data):
        async for chunk in response:
            yield chunk


async def _failing_upstream(items, error):
    for item in items:
        yield item
    raise error


async def _drain_into(stream, out):
    async for chunk in stream:
        out.append(chunk)


async def test_streaming_hook_error_before_first_output_fails_open(pipeline_module, fake_litellm):
    pipeline = pipeline_module.MiddlewarePipeline((MidStreamFailingMiddleware(),))

    out = [c async for c in pipeline.async_post_call_streaming_iterator_hook(
        None, _stream(["a", "b", "c"]), {})]

    assert out == ["a", "b", "c"]
    assert "RuntimeError" in fake_litellm.verbose_proxy_logger.warnings[-1][0]


async def test_streaming_hook_error_mid_stream_can_fail_closed(pipeline_module):
    pipeline = pipeline_module.MiddlewarePipeline((MidStreamFailingMiddleware(),), fail_open=False)

    stream = pipeline.async_post_call_streaming_iterator_hook(None, _stream(["a", "b"]), {})

    with pytest.raises(RuntimeError):
        await _drain_into(stream, [])


async def test_streaming_hook_does_not_swallow_upstream_errors(pipeline_module):
    pipeline = pipeline_module.MiddlewarePipeline((PassThroughStreamMiddleware(),))

    stream = pipeline.async_post_call_streaming_iterator_hook(
        None, _failing_upstream(["a"], ValueError("provider down")), {})
    out = []

    with pytest.raises(ValueError):
        await _drain_into(stream, out)

    assert out == ["a"]


class FailAtEndMiddleware:
    async def async_post_call_streaming_iterator_hook(self, user_api_key_dict, response, request_data):
        async for _ in response:
            pass
        raise RuntimeError("boom")
        yield


class CountingStream:
    def __init__(self, items):
        self.items = list(items)
        self.polls_after_end = 0

    def __aiter__(self):
        return self

    async def __anext__(self):
        if self.items:
            return self.items.pop(0)
        self.polls_after_end += 1
        raise StopAsyncIteration


async def test_fail_open_does_not_poll_an_exhausted_upstream_again(pipeline_module):
    upstream = CountingStream(["a", "b"])
    pipeline = pipeline_module.MiddlewarePipeline((FailAtEndMiddleware(),))

    out = [c async for c in pipeline.async_post_call_streaming_iterator_hook(None, upstream, {})]

    assert out == ["a", "b"]
    assert upstream.polls_after_end == 1


class SseBufferingMiddleware:
    async def async_post_call_streaming_iterator_hook(self, user_api_key_dict, response, request_data):
        buffer = ""
        async for chunk in response:
            if "fail" in chunk:
                raise RuntimeError("boom")
            buffer += chunk
            *events, buffer = buffer.split("\n\n")
            for event in events:
                yield event + "\n\n"
        if buffer:
            yield buffer


async def test_streaming_hook_error_after_output_fails_closed_instead_of_dropping_buffered_data(pipeline_module):
    pipeline = pipeline_module.MiddlewarePipeline((SseBufferingMiddleware(),))

    stream = pipeline.async_post_call_streaming_iterator_hook(
        None, _stream(["data: 1\n\ndata: 2", "\n\nfail\n\n", "data: 3\n\n"]), {})
    out = []

    with pytest.raises(RuntimeError, match="boom"):
        await _drain_into(stream, out)

    assert out == ["data: 1\n\n"]


class DecliningUpperStreamMiddleware(UpperStreamMiddleware):
    def __init__(self):
        self.asked = []

    def wants_stream(self, request_data):
        self.asked.append(request_data)
        return False


async def test_streaming_returns_upstream_untouched_when_no_middleware_wants_it(pipeline_module):
    middleware = DecliningUpperStreamMiddleware()
    pipeline = pipeline_module.MiddlewarePipeline((middleware,))
    upstream = _stream(["a"])

    out = pipeline.async_post_call_streaming_iterator_hook(None, upstream, {"id": 1})

    assert out is upstream
    assert middleware.asked == [{"id": 1}]


class BrokenWantsUpperStreamMiddleware(UpperStreamMiddleware):
    def wants_stream(self, request_data):
        raise RuntimeError("boom")


async def test_wants_stream_error_fails_open_by_still_applying_the_middleware(pipeline_module, fake_litellm):
    pipeline = pipeline_module.MiddlewarePipeline((BrokenWantsUpperStreamMiddleware(),))

    out = [c async for c in pipeline.async_post_call_streaming_iterator_hook(None, _stream(["a"]), {})]

    assert out == ["A"]
    assert "RuntimeError" in fake_litellm.verbose_proxy_logger.warnings[-1][0]


async def test_wants_stream_error_can_fail_closed(pipeline_module):
    pipeline = pipeline_module.MiddlewarePipeline((BrokenWantsUpperStreamMiddleware(),), fail_open=False)

    upstream = _stream(["a"])

    with pytest.raises(RuntimeError, match="boom"):
        pipeline.async_post_call_streaming_iterator_hook(None, upstream, {})


class CleanupRecordingMiddleware:
    def __init__(self):
        self.cleaned_up = False

    async def async_post_call_streaming_iterator_hook(self, user_api_key_dict, response, request_data):
        try:
            async for chunk in response:
                yield chunk
        finally:
            self.cleaned_up = True


async def test_closing_stream_early_closes_middleware_and_upstream_immediately(pipeline_module):
    upstream_closed = []

    async def upstream():
        try:
            for item in ["a", "b", "c"]:
                yield item
        finally:
            upstream_closed.append(True)

    middleware = CleanupRecordingMiddleware()
    pipeline = pipeline_module.MiddlewarePipeline((middleware,))
    stream = pipeline.async_post_call_streaming_iterator_hook(None, upstream(), {})

    assert await stream.__anext__() == "a"
    await stream.aclose()

    assert middleware.cleaned_up is True
    assert upstream_closed == [True]


class FailingCleanupMiddleware:
    async def async_post_call_streaming_iterator_hook(self, user_api_key_dict, response, request_data):
        try:
            async for chunk in response:
                yield chunk
        finally:
            raise RuntimeError("cleanup boom")


async def test_middleware_cleanup_error_still_closes_upstream_and_is_not_raised(pipeline_module, fake_litellm):
    upstream_closed = []

    async def upstream():
        try:
            yield "a"
            yield "b"
        finally:
            upstream_closed.append(True)

    pipeline = pipeline_module.MiddlewarePipeline((FailingCleanupMiddleware(),))
    stream = pipeline.async_post_call_streaming_iterator_hook(None, upstream(), {})

    assert await stream.__anext__() == "a"
    await stream.aclose()

    assert upstream_closed == [True]
    assert "RuntimeError" in fake_litellm.verbose_proxy_logger.warnings[-1][0]
