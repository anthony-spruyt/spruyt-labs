from __future__ import annotations

from typing import Any, Optional, Protocol, Union


PreCallResult = Optional[Union[Exception, dict, str]]


class ProxyMiddleware(Protocol):
    async def async_pre_call_hook(
        self,
        user_api_key_dict: Any,
        cache: Any,
        data: dict,
        call_type: str,
    ) -> PreCallResult:
        ...

    async def async_log_success_event(
        self,
        kwargs: dict,
        response_obj: Any,
        start_time: Any,
        end_time: Any,
    ) -> None:
        ...
