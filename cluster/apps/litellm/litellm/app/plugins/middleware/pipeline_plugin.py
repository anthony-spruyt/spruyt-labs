"""LiteLLM callback entrypoint for composable proxy middleware."""

from __future__ import annotations

from litellm._logging import verbose_proxy_logger

from custom_callbacks.middleware.pipeline import MiddlewarePipeline
from custom_callbacks.middleware.registry import load_default_middlewares


pipeline_middleware = MiddlewarePipeline(
    load_default_middlewares(logger=verbose_proxy_logger)
)
