"""Lists a cold MCP server's tools before a tool call so a fresh LiteLLM worker can route it."""

from __future__ import annotations

import asyncio
import logging
from typing import Any, Callable


_PATCH_MARKER = "_mcp_tool_routing_patch"
_MANAGER_API = ("_get_tools_from_server", "_server_exposes_tool")
_UTILS_API = (
    "normalize_server_name", "iter_known_server_prefixes", "match_known_server_prefix", "strip_known_server_prefix")
# Same logger object as litellm._logging.verbose_proxy_logger.
_logger = logging.getLogger("LiteLLM Proxy")


class McpToolMappingWarmer:
    def __init__(self, manager: Any, utils: Any, prepare_headers: Callable[..., Any], logger: Any) -> None:
        self._manager = manager
        self._utils = utils
        self._prepare_headers = prepare_headers
        self._logger = logger
        self._locks: dict[str, asyncio.Lock] = {}
        self._attempts: dict[str, int] = {}

    def _target_server(self, name: str, servers: list[Any], requested_server_id: str | None) -> Any:
        if requested_server_id:
            return next((s for s in servers if s.server_id == requested_server_id), None)
        by_prefix: dict[str, Any] = {}
        for server in servers:
            for prefix in self._utils.iter_known_server_prefixes(server):
                by_prefix.setdefault(self._utils.normalize_server_name(prefix), server)
        matched = self._utils.match_known_server_prefix(name, by_prefix.keys())
        return by_prefix.get(matched[0]) if matched else None

    def _is_cold(self, server: Any, name: str) -> bool:
        return not self._manager._server_exposes_tool(server, self._utils.strip_known_server_prefix(name, server))

    async def warm(self, name: str, servers: list[Any], **context: Any) -> None:
        try:
            await self._warm(name, servers, **context)
        except Exception as exc:  # noqa: BLE001 - the call itself still runs and reports its own error
            self._logger.warning("MCP tool mapping warm-up failed for %s: %s", name, exc)

    async def _warm(
        self,
        name: str,
        servers: list[Any],
        *,
        requested_server_id: str | None = None,
        mcp_auth_header: Any = None,
        mcp_server_auth_headers: Any = None,
        oauth2_headers: Any = None,
        raw_headers: Any = None,
        user_api_key_auth: Any = None,
    ) -> None:
        server = self._target_server(name, servers, requested_server_id)
        if server is None or not self._is_cold(server, name):
            return
        attempt = self._attempts.get(server.server_id, 0)
        async with self._locks.setdefault(server.server_id, asyncio.Lock()):
            # A listing that ran while this caller waited covers it, even if that listing failed.
            if self._attempts.get(server.server_id, 0) != attempt or not self._is_cold(server, name):
                return
            try:
                auth_header, extra_headers = self._prepare_headers(
                    server=server,
                    mcp_server_auth_headers=mcp_server_auth_headers,
                    mcp_auth_header=mcp_auth_header,
                    oauth2_headers=oauth2_headers,
                    raw_headers=raw_headers,
                    user_api_key_auth=user_api_key_auth,
                )
                await self._manager._get_tools_from_server(
                    server,
                    mcp_auth_header=auth_header,
                    extra_headers=extra_headers,
                    add_prefix=True,
                    raw_headers=raw_headers,
                    user_api_key_auth=user_api_key_auth,
                    oauth2_headers=oauth2_headers,
                )
            finally:
                self._attempts[server.server_id] = attempt + 1


def wrap_execute_mcp_tool(original: Callable[..., Any], warmer: McpToolMappingWarmer) -> Callable[..., Any]:
    async def execute_mcp_tool(**kwargs: Any) -> Any:
        await warmer.warm(
            kwargs["name"],
            kwargs.get("allowed_mcp_servers") or [],
            requested_server_id=kwargs.get("requested_server_id"),
            mcp_auth_header=kwargs.get("mcp_auth_header"),
            mcp_server_auth_headers=kwargs.get("mcp_server_auth_headers"),
            oauth2_headers=kwargs.get("oauth2_headers"),
            raw_headers=kwargs.get("raw_headers"),
            user_api_key_auth=kwargs.get("user_api_key_auth"),
        )
        return await original(**kwargs)

    setattr(execute_mcp_tool, _PATCH_MARKER, True)
    return execute_mcp_tool


def install_mcp_tool_routing_patch() -> bool:
    # Workaround for #3306 (BerriAI/litellm#44373): remove once a LiteLLM release
    # includes _list_tools_before_first_call (operations.py).
    try:
        import litellm
    except ModuleNotFoundError as exc:
        if exc.name == "litellm":
            return False
        raise
    if not hasattr(litellm, "__path__"):
        return False

    try:
        from litellm.proxy._experimental.mcp_server import rest_endpoints, server, utils
        from litellm.proxy._experimental.mcp_server.mcp_server_manager import global_mcp_server_manager

        original = server.execute_mcp_tool
        prepare_headers = server._prepare_mcp_server_headers
        for owner, names in ((global_mcp_server_manager, _MANAGER_API), (utils, _UTILS_API)):
            for attr in names:
                getattr(owner, attr)
    except (ImportError, AttributeError) as exc:
        _logger.warning("MCP tool routing patch not installed, LiteLLM internals changed: %s", exc)
        return False

    if not getattr(original, _PATCH_MARKER, False):
        warmer = McpToolMappingWarmer(global_mcp_server_manager, utils, prepare_headers, _logger)
        server.execute_mcp_tool = wrap_execute_mcp_tool(original, warmer)

    # rest_endpoints binds execute_mcp_tool at import time.
    rest_endpoints.execute_mcp_tool = server.execute_mcp_tool
    return True


class McpToolRoutingMiddleware:
    """Defines no pipeline hooks; importing the module installs the patch."""


install_mcp_tool_routing_patch()
mcp_tool_routing = McpToolRoutingMiddleware()
