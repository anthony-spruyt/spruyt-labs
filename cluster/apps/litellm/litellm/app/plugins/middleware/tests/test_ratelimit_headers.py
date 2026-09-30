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


@pytest.fixture
def module():
    sys.modules.pop("ratelimit_headers", None)
    return importlib.import_module("ratelimit_headers")


class StreamingResponse:
    def __init__(self, additional_headers):
        self._hidden_params = {"additional_headers": additional_headers}


def _logged(headers):
    logging_obj = SimpleNamespace(
        model_call_details={"httpx_response": httpx.Response(200, headers=headers)})
    return {"litellm_logging_obj": logging_obj}


async def _hook(module, data, response):
    return await module.ratelimit_headers.async_post_call_response_headers_hook(
        data=data, user_api_key_dict=None, response=response, request_headers={})


async def test_streaming_restores_unified_headers_from_hidden_params(module):
    response = StreamingResponse({
        "llm_provider-anthropic-ratelimit-unified-status": "allowed",
        "llm_provider-anthropic-ratelimit-unified-5h-utilization": "0.42",
        "llm_provider-anthropic-ratelimit-unified-7d-reset": "1790000000",
    })

    out = await _hook(module, {}, response)

    assert out == {
        "anthropic-ratelimit-unified-status": "allowed",
        "anthropic-ratelimit-unified-5h-utilization": "0.42",
        "anthropic-ratelimit-unified-7d-reset": "1790000000",
    }


async def test_streaming_leaves_other_provider_headers_alone(module):
    response = StreamingResponse({
        "llm_provider-anthropic-ratelimit-unified-status": "allowed",
        "llm_provider-request-id": "req_1",
        "llm_provider-anthropic-ratelimit-requests-limit": "50",
        "x-ratelimit-limit-requests": "50",
    })

    out = await _hook(module, {}, response)

    assert out == {"anthropic-ratelimit-unified-status": "allowed"}


async def test_non_streaming_restores_unified_headers_from_raw_upstream_response(module):
    data = _logged({
        "anthropic-ratelimit-unified-status": "allowed",
        "anthropic-ratelimit-unified-7d-utilization": "0.1",
        "request-id": "req_1",
    })

    out = await _hook(module, data, {"type": "message"})

    assert out == {
        "anthropic-ratelimit-unified-status": "allowed",
        "anthropic-ratelimit-unified-7d-utilization": "0.1",
    }


async def test_streaming_without_unified_headers_returns_none(module):
    response = StreamingResponse({"llm_provider-request-id": "req_1"})

    assert await _hook(module, _logged({"request-id": "req_1"}), response) is None


async def test_non_streaming_without_unified_headers_returns_none(module):
    assert await _hook(module, _logged({"request-id": "req_1"}), {"type": "message"}) is None


async def test_failure_without_response_or_logging_obj_returns_none(module):
    assert await _hook(module, {}, None) is None
