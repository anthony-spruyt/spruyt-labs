"""Restore Anthropic's unified rate-limit headers that LiteLLM renames to llm_provider-*."""

from __future__ import annotations

from typing import Any, Optional


_UNIFIED = "anthropic-ratelimit-unified-"
_PREFIXED = "llm_provider-" + _UNIFIED


class RatelimitHeadersMiddleware:
    async def async_post_call_response_headers_hook(
        self, data: dict, user_api_key_dict: Any, response: Any, request_headers=None, litellm_call_info=None
    ) -> Optional[dict[str, str]]:
        headers = {**_from_upstream_response(data), **_from_hidden_params(response)}
        return headers or None


def _from_hidden_params(response: Any) -> dict[str, str]:
    hidden = response.get("_hidden_params") if isinstance(response, dict) else getattr(response, "_hidden_params", None)
    additional = (hidden or {}).get("additional_headers") if isinstance(hidden, dict) else None
    return {
        k[len("llm_provider-"):]: str(v)
        for k, v in (additional or {}).items()
        if isinstance(k, str) and k.lower().startswith(_PREFIXED)
    }


# Non-streamed /v1/messages replies are plain dicts whose _hidden_params the proxy strips before this hook.
def _from_upstream_response(data: Any) -> dict[str, str]:
    logging_obj = data.get("litellm_logging_obj") if isinstance(data, dict) else None
    details = getattr(logging_obj, "model_call_details", None)
    upstream = details.get("httpx_response") if isinstance(details, dict) else None
    headers = getattr(upstream, "headers", None)
    if headers is None:
        return {}
    return {k.lower(): str(v) for k, v in headers.items() if k.lower().startswith(_UNIFIED)}


ratelimit_headers = RatelimitHeadersMiddleware()
