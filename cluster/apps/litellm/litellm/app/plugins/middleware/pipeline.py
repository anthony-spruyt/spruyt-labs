from __future__ import annotations

import inspect
from typing import Any, Iterable

from litellm._logging import verbose_proxy_logger
from litellm.integrations.custom_logger import CustomLogger


class MiddlewarePipeline(CustomLogger):
    def __init__(self, middlewares: Iterable[Any], *, fail_open: bool = True) -> None:
        super().__init__()
        self.middlewares = tuple(middlewares)
        self.fail_open = fail_open

    async def async_pre_call_hook(self, user_api_key_dict, cache, data: dict, call_type: str):
        for middleware in self.middlewares:
            hook = getattr(middleware, "async_pre_call_hook", None)
            if hook is None:
                continue

            try:
                result = hook(user_api_key_dict, cache, data, call_type)
                if inspect.isawaitable(result):
                    result = await result
            except Exception as exc:  # noqa: BLE001 - middleware should not break proxy traffic
                if not self.fail_open:
                    raise
                self._log_warning("%s pre-call failed open: %s", middleware, type(exc).__name__)
                continue

            if isinstance(result, (Exception, str)):
                return result
            if isinstance(result, dict):
                data = result
            elif result is not None:
                self._log_warning(
                    "%s returned unsupported pre-call result %r; ignoring",
                    middleware,
                    type(result).__name__,
                )
        return data

    async def async_post_call_success_hook(self, data: dict, user_api_key_dict, response):
        for middleware in self.middlewares:
            hook = getattr(middleware, "async_post_call_success_hook", None)
            if hook is None:
                continue

            try:
                result = hook(data=data, user_api_key_dict=user_api_key_dict, response=response)
                if inspect.isawaitable(result):
                    result = await result
            except Exception as exc:  # noqa: BLE001 - middleware should not break proxy traffic
                if not self.fail_open:
                    raise
                self._log_warning("%s post-call failed open: %s", middleware, type(exc).__name__)
                continue

            if result is not None:
                response = result
        return response

    async def async_post_call_streaming_iterator_hook(self, user_api_key_dict, response, request_data: dict):
        stream = response
        for middleware in self.middlewares:
            hook = getattr(middleware, "async_post_call_streaming_iterator_hook", None)
            if hook is None:
                continue

            try:
                stream = hook(
                    user_api_key_dict=user_api_key_dict,
                    response=stream,
                    request_data=request_data,
                )
            except Exception as exc:  # noqa: BLE001 - middleware should not break proxy traffic
                if not self.fail_open:
                    raise
                self._log_warning("%s streaming hook failed open: %s", middleware, type(exc).__name__)

        async for chunk in stream:
            yield chunk

    async def async_post_call_failure_hook(
        self, request_data: dict, original_exception, user_api_key_dict, traceback_str=None
    ):
        for middleware in self.middlewares:
            hook = getattr(middleware, "async_post_call_failure_hook", None)
            if hook is None:
                continue

            try:
                result = hook(
                    request_data=request_data,
                    original_exception=original_exception,
                    user_api_key_dict=user_api_key_dict,
                    traceback_str=traceback_str,
                )
                if inspect.isawaitable(result):
                    await result
            except Exception as exc:  # noqa: BLE001 - failure hooks must never mask the original error
                if not self.fail_open:
                    raise
                self._log_warning("%s failure hook failed open: %s", middleware, type(exc).__name__)

    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        for middleware in self.middlewares:
            hook = getattr(middleware, "async_log_success_event", None)
            if hook is None:
                continue

            try:
                result = hook(kwargs, response_obj, start_time, end_time)
                if inspect.isawaitable(result):
                    await result
            except Exception as exc:  # noqa: BLE001 - success logging must never fail responses
                if not self.fail_open:
                    raise
                self._log_warning("%s success hook failed open: %s", middleware, type(exc).__name__)

    @staticmethod
    def _log_warning(message: str, *args: Any) -> None:
        try:
            verbose_proxy_logger.warning(message, *args)
        except Exception:  # noqa: BLE001 - logging should never affect request handling
            return
