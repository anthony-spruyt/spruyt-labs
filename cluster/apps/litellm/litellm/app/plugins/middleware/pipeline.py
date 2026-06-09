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
                self._log_warning("%s pre-call failed open: %s", middleware, exc)
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
                self._log_warning("%s success hook failed open: %s", middleware, exc)

    @staticmethod
    def _log_warning(message: str, *args: Any) -> None:
        try:
            verbose_proxy_logger.warning(message, *args)
        except Exception:  # noqa: BLE001 - logging should never affect request handling
            return
