from __future__ import annotations

import contextvars
import json
import os
import time
from functools import lru_cache
from typing import Any


_DEFAULT_CONFIG_PATH = "/app/config.yaml"
_ROUTED_CHATGPT_RESPONSES_MODELS = {
    "gpt-5.5",
    "gpt-5.4-mini",
}

_CHATGPT_RESPONSES_TRANSPORT_STREAM = contextvars.ContextVar(
    "chatgpt_responses_transport_stream",
    default=False,
)


def _config_path() -> str:
    return os.getenv("CHATGPT_CONFIG_PATH") or os.getenv(
        "LITELLM_CONFIG_PATH", _DEFAULT_CONFIG_PATH)


@lru_cache(maxsize=4)
def _load_config(path: str) -> dict:
    if not path or not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as handle:
        raw = handle.read()
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        try:
            import yaml  # type: ignore[import-untyped]
        except ImportError:
            return {}
        parsed = yaml.safe_load(raw)
    return parsed if isinstance(parsed, dict) else {}


def _resolve_alias(config: dict, model: str) -> str | None:
    aliases = (config.get("router_settings") or {}).get("model_group_alias") or {}
    if not isinstance(aliases, dict) or model not in aliases:
        return None
    target = aliases[model]
    if isinstance(target, str):
        return target
    if isinstance(target, dict) and isinstance(target.get("model"), str):
        return target["model"]
    return None


def _resolve_model_list_entry(config: dict, model: str) -> str | None:
    model_list = config.get("model_list") or []
    if not isinstance(model_list, list):
        return None
    for entry in model_list:
        if not isinstance(entry, dict) or entry.get("model_name") != model:
            continue
        litellm_params = entry.get("litellm_params") or {}
        target = litellm_params.get("model")
        return target if isinstance(target, str) else None
    return None


@lru_cache(maxsize=16)
def _resolve_configured_model(model: str) -> str:
    current = model
    seen = set()
    config = _load_config(_config_path())
    while current not in seen:
        seen.add(current)
        target = _resolve_alias(config, current) or _resolve_model_list_entry(
            config, current)
        if not target:
            return current
        current = target
    return current


def _strip_chatgpt_responses_prefix(model: str) -> str:
    return model.removeprefix("chatgpt/").removeprefix("responses/")


@lru_cache(maxsize=16)
def _is_chatgpt_responses_alias(model: Any) -> bool:
    if not isinstance(model, str):
        return False
    resolved = _resolve_configured_model(model)
    return _strip_chatgpt_responses_prefix(resolved) in _ROUTED_CHATGPT_RESPONSES_MODELS


def _force_http_stream_kwargs(kwargs: dict[str, Any]) -> None:
    kwargs["stream"] = True
    payload = kwargs.get("json")
    if isinstance(payload, dict):
        payload = dict(payload)
        payload["stream"] = True
        kwargs["json"] = payload


def _completed_responses_api_response(result: Any) -> Any:
    from litellm.types.llms.openai import ResponseCompletedEvent, ResponsesAPIResponse

    completed = getattr(result, "completed_response", None)
    if isinstance(completed, ResponseCompletedEvent):
        return completed.response
    if isinstance(completed, ResponsesAPIResponse):
        return completed

    response = getattr(completed, "response", None)
    if isinstance(response, ResponsesAPIResponse):
        return response
    raise ValueError(f"Expected completed ResponsesAPIResponse, got {type(completed)}")


def _record_stream_chunks(result: Any) -> tuple[list[str], Any]:
    chunks: list[str] = []
    original_process_chunk = result._process_chunk

    def _recording_process_chunk(chunk: Any) -> Any:
        if isinstance(chunk, bytes):
            chunks.append(chunk.decode("utf-8", errors="replace"))
        elif isinstance(chunk, str):
            chunks.append(chunk)
        return original_process_chunk(chunk)

    result._process_chunk = _recording_process_chunk
    return chunks, original_process_chunk


def _recover_empty_output_from_chunks(completed: Any, chunks: list[str]) -> Any:
    output = getattr(completed, "output", None)
    if output or not chunks:
        return completed

    from litellm.completion_extras.litellm_responses_transformation.transformation import (
        LiteLLMResponsesTransformationHandler,
    )

    recovered = LiteLLMResponsesTransformationHandler._recover_output_items_from_raw_sse(
        "\n".join(chunks)
    )
    if recovered:
        completed.output = recovered
    return completed


async def _collect_forced_responses_result(result: Any, logging_obj: Any) -> Any:
    from litellm.responses.streaming_iterator import BaseResponsesAPIStreamingIterator

    if not isinstance(result, BaseResponsesAPIStreamingIterator):
        return result

    result._completed_response_logged = True
    chunks, original_process_chunk = _record_stream_chunks(result)
    try:
        async for _ in result:
            pass
    finally:
        result._process_chunk = original_process_chunk

    completed = _recover_empty_output_from_chunks(
        _completed_responses_api_response(result), chunks)
    await logging_obj.async_success_handler(result=completed)
    return completed


def _collect_forced_responses_result_sync(result: Any, logging_obj: Any) -> Any:
    from litellm.responses.streaming_iterator import BaseResponsesAPIStreamingIterator

    if not isinstance(result, BaseResponsesAPIStreamingIterator):
        return result

    result._completed_response_logged = True
    chunks, original_process_chunk = _record_stream_chunks(result)
    try:
        for _ in result:
            pass
    finally:
        result._process_chunk = original_process_chunk

    completed = _recover_empty_output_from_chunks(
        _completed_responses_api_response(result), chunks)
    logging_obj.success_handler(result=completed)
    return completed


def _patch_anthropic_responses_routing() -> None:
    from litellm.llms.anthropic.experimental_pass_through.messages import (
        handler as anthropic_messages_handler,
    )

    providers = getattr(anthropic_messages_handler, "_RESPONSES_API_PROVIDERS", frozenset())
    if "chatgpt" in providers:
        return
    anthropic_messages_handler._RESPONSES_API_PROVIDERS = frozenset(
        {"chatgpt", *providers}
    )


def _patch_responses_bridge() -> None:
    import litellm.main as litellm_main

    if getattr(litellm_main, "_chatgpt_responses_bridge_patch", False):
        return

    original = litellm_main.responses_api_bridge_check

    def _patched_responses_api_bridge_check(
        model: str,
        custom_llm_provider: str,
        *args: Any,
        **kwargs: Any,
    ) -> tuple[dict, str]:
        model_info, resolved_model = original(
            model=model,
            custom_llm_provider=custom_llm_provider,
            *args,
            **kwargs,
        )
        if custom_llm_provider == "chatgpt" and _is_chatgpt_responses_alias(resolved_model):
            model_info["mode"] = "responses"
            return model_info, _strip_chatgpt_responses_prefix(resolved_model)
        return model_info, resolved_model

    litellm_main.responses_api_bridge_check = _patched_responses_api_bridge_check
    litellm_main._chatgpt_responses_bridge_patch = True


def _patch_responses_transport() -> None:
    import litellm
    from litellm.llms.custom_httpx import llm_http_handler
    from litellm.llms.custom_httpx.http_handler import AsyncHTTPHandler, HTTPHandler

    handler_cls = llm_http_handler.BaseLLMHTTPHandler
    if getattr(handler_cls, "_chatgpt_responses_transport_patch", False):
        return

    original_sync = handler_cls.response_api_handler
    original_async = handler_cls.async_response_api_handler
    original_async_http_post = AsyncHTTPHandler.post
    original_sync_http_post = HTTPHandler.post

    def _should_force(model: str, custom_llm_provider: str) -> bool:
        return custom_llm_provider == "chatgpt" and _is_chatgpt_responses_alias(model)

    def _prepare_forced_params(params: dict[str, Any]) -> dict[str, Any]:
        forced_params = dict(params)
        forced_params["stream"] = True
        return forced_params

    async def _patched_async_http_post(self: Any, *args: Any, **kwargs: Any) -> Any:
        if _CHATGPT_RESPONSES_TRANSPORT_STREAM.get():
            _force_http_stream_kwargs(kwargs)
        return await original_async_http_post(self, *args, **kwargs)

    def _patched_sync_http_post(self: Any, *args: Any, **kwargs: Any) -> Any:
        if _CHATGPT_RESPONSES_TRANSPORT_STREAM.get():
            _force_http_stream_kwargs(kwargs)
        return original_sync_http_post(self, *args, **kwargs)

    async def _patched_async_response_api_handler(
        self: Any,
        model: str,
        input: Any,
        responses_api_provider_config: Any,
        response_api_optional_request_params: dict,
        custom_llm_provider: str,
        litellm_params: Any,
        logging_obj: Any,
        extra_headers: dict[str, Any] | None = None,
        extra_body: dict[str, Any] | None = None,
        timeout: float | Any | None = None,
        client: Any | None = None,
        fake_stream: bool = False,
        litellm_metadata: dict[str, Any] | None = None,
        shared_session: Any | None = None,
    ) -> Any:
        if not _should_force(model, custom_llm_provider):
            return await original_async(
                self,
                model=model,
                input=input,
                responses_api_provider_config=responses_api_provider_config,
                response_api_optional_request_params=response_api_optional_request_params,
                custom_llm_provider=custom_llm_provider,
                litellm_params=litellm_params,
                logging_obj=logging_obj,
                extra_headers=extra_headers,
                extra_body=extra_body,
                timeout=timeout,
                client=client,
                fake_stream=fake_stream,
                litellm_metadata=litellm_metadata,
                shared_session=shared_session,
            )

        original_stream = bool(response_api_optional_request_params.get("stream", False))
        token = _CHATGPT_RESPONSES_TRANSPORT_STREAM.set(True)
        try:
            result = await original_async(
                self,
                model=model,
                input=input,
                responses_api_provider_config=responses_api_provider_config,
                response_api_optional_request_params=_prepare_forced_params(
                    response_api_optional_request_params),
                custom_llm_provider=custom_llm_provider,
                litellm_params=litellm_params,
                logging_obj=logging_obj,
                extra_headers=extra_headers,
                extra_body=extra_body,
                timeout=timeout,
                client=client,
                fake_stream=False,
                litellm_metadata=litellm_metadata,
                shared_session=shared_session,
            )
        finally:
            _CHATGPT_RESPONSES_TRANSPORT_STREAM.reset(token)

        if original_stream:
            return result
        return await _collect_forced_responses_result(result, logging_obj)

    def _patched_response_api_handler(
        self: Any,
        model: str,
        input: Any,
        responses_api_provider_config: Any,
        response_api_optional_request_params: dict,
        custom_llm_provider: str,
        litellm_params: Any,
        logging_obj: Any,
        extra_headers: dict[str, Any] | None = None,
        extra_body: dict[str, Any] | None = None,
        timeout: float | Any | None = None,
        client: Any | None = None,
        _is_async: bool = False,
        fake_stream: bool = False,
        litellm_metadata: dict[str, Any] | None = None,
        shared_session: Any | None = None,
    ) -> Any:
        should_force = _should_force(model, custom_llm_provider)

        if _is_async:
            if should_force:
                return _patched_async_response_api_handler(
                    self,
                    model=model,
                    input=input,
                    responses_api_provider_config=responses_api_provider_config,
                    response_api_optional_request_params=response_api_optional_request_params,
                    custom_llm_provider=custom_llm_provider,
                    litellm_params=litellm_params,
                    logging_obj=logging_obj,
                    extra_headers=extra_headers,
                    extra_body=extra_body,
                    timeout=timeout,
                    client=client,
                    fake_stream=fake_stream,
                    litellm_metadata=litellm_metadata,
                    shared_session=shared_session,
                )
            return original_sync(
                self,
                model=model,
                input=input,
                responses_api_provider_config=responses_api_provider_config,
                response_api_optional_request_params=response_api_optional_request_params,
                custom_llm_provider=custom_llm_provider,
                litellm_params=litellm_params,
                logging_obj=logging_obj,
                extra_headers=extra_headers,
                extra_body=extra_body,
                timeout=timeout,
                client=client,
                _is_async=True,
                fake_stream=fake_stream,
                litellm_metadata=litellm_metadata,
                shared_session=shared_session,
            )

        if not should_force:
            return original_sync(
                self,
                model=model,
                input=input,
                responses_api_provider_config=responses_api_provider_config,
                response_api_optional_request_params=response_api_optional_request_params,
                custom_llm_provider=custom_llm_provider,
                litellm_params=litellm_params,
                logging_obj=logging_obj,
                extra_headers=extra_headers,
                extra_body=extra_body,
                timeout=timeout,
                client=client,
                _is_async=False,
                fake_stream=fake_stream,
                litellm_metadata=litellm_metadata,
                shared_session=shared_session,
            )

        original_stream = bool(response_api_optional_request_params.get("stream", False))
        token = _CHATGPT_RESPONSES_TRANSPORT_STREAM.set(True)
        try:
            result = original_sync(
                self,
                model=model,
                input=input,
                responses_api_provider_config=responses_api_provider_config,
                response_api_optional_request_params=_prepare_forced_params(
                    response_api_optional_request_params),
                custom_llm_provider=custom_llm_provider,
                litellm_params=litellm_params,
                logging_obj=logging_obj,
                extra_headers=extra_headers,
                extra_body=extra_body,
                timeout=timeout,
                client=client,
                _is_async=False,
                fake_stream=False,
                litellm_metadata=litellm_metadata,
                shared_session=shared_session,
            )
        finally:
            _CHATGPT_RESPONSES_TRANSPORT_STREAM.reset(token)

        if original_stream:
            return result
        return _collect_forced_responses_result_sync(result, logging_obj)

    AsyncHTTPHandler.post = _patched_async_http_post
    HTTPHandler.post = _patched_sync_http_post
    handler_cls.async_response_api_handler = _patched_async_response_api_handler
    handler_cls.response_api_handler = _patched_response_api_handler
    handler_cls._chatgpt_responses_transport_patch = True


def _build_fallback_model_response_for_responses_logging(logging_obj: Any, result: Any) -> Any:
    import litellm
    from litellm.types.utils import Choices, Message, Usage

    model_response = litellm.ModelResponse()
    model_response.model = logging_obj.model
    model_response.created = int(time.time())
    model_response.choices = [
        Choices(
            index=0,
            finish_reason="stop",
            message=Message(
                role="assistant",
                content=getattr(result, "output_text", "") or "",
            ),
        )
    ]

    usage = getattr(result, "usage", None)
    if usage is not None:
        model_response.usage = Usage(
            prompt_tokens=getattr(usage, "input_tokens", None),
            completion_tokens=getattr(usage, "output_tokens", None),
            total_tokens=getattr(usage, "total_tokens", None),
        )

    return model_response


def _transform_responses_result_for_anthropic_logging(logging_obj: Any, result: Any) -> Any:
    import litellm
    from litellm.completion_extras.litellm_responses_transformation.transformation import (
        LiteLLMResponsesTransformationHandler,
    )
    from litellm.types.llms.openai import ResponseCompletedEvent, ResponsesAPIResponse

    if isinstance(result, ResponseCompletedEvent):
        result = result.response
    if not isinstance(result, ResponsesAPIResponse):
        return result

    try:
        return LiteLLMResponsesTransformationHandler().transform_response(
            model=logging_obj.model,
            raw_response=result,
            model_response=litellm.ModelResponse(),
            logging_obj=logging_obj,
            request_data={},
            messages=[],
            optional_params={},
            litellm_params={},
            encoding=litellm.encoding,
            json_mode=False,
        )
    except ValueError as exc:
        if "Unknown items in responses API response" not in str(exc):
            raise
        return _build_fallback_model_response_for_responses_logging(logging_obj, result)


def _patch_anthropic_response_logging() -> None:
    from litellm.litellm_core_utils.litellm_logging import Logging

    if getattr(Logging, "_chatgpt_anthropic_responses_logging_patch", False):
        return

    original = Logging._handle_anthropic_messages_response_logging

    def _patched_handle_anthropic_messages_response_logging(self: Any, result: Any) -> Any:
        transformed = _transform_responses_result_for_anthropic_logging(self, result)
        if transformed is not result:
            return transformed
        return original(self, transformed)

    Logging._handle_anthropic_messages_response_logging = (
        _patched_handle_anthropic_messages_response_logging
    )
    Logging._chatgpt_anthropic_responses_logging_patch = True


def install_litellm_patches() -> bool:
    try:
        import litellm
    except ModuleNotFoundError as exc:
        if exc.name == "litellm":
            return False
        raise
    if not hasattr(litellm, "__path__"):
        return False

    _patch_anthropic_responses_routing()
    _patch_responses_bridge()
    _patch_responses_transport()
    _patch_anthropic_response_logging()
    return True
