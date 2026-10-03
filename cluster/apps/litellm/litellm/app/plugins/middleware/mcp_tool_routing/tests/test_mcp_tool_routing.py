import asyncio
import importlib
import os
import sys
import types
from types import SimpleNamespace

import pytest


_HERE = os.path.dirname(__file__)
_PLUGINS_DIR = os.path.dirname(os.path.dirname(os.path.dirname(_HERE)))
if _PLUGINS_DIR not in sys.path:
    sys.path.insert(0, _PLUGINS_DIR)


class FakeUtils:
    @staticmethod
    def normalize_server_name(name):
        return name.replace(" ", "_")

    @staticmethod
    def iter_known_server_prefixes(server):
        yield server.name

    @staticmethod
    def match_known_server_prefix(name, known_prefixes):
        for prefix in sorted(known_prefixes, key=len, reverse=True):
            if name.startswith(prefix + "-"):
                return prefix, name[len(prefix) + 1:]
        return None

    @staticmethod
    def strip_known_server_prefix(name, server):
        return name.removeprefix(server.name + "-")


class FakeManager:
    def __init__(self, tools=("query",), gate=None, error=None):
        self.tool_name_to_mcp_server_name_mapping = {}
        self.list_calls = []
        self._tools = tools
        self._gate = gate
        self._error = error

    def _server_exposes_tool(self, server, tool_name):
        spellings = (tool_name, f"{server.name}-{tool_name}")
        return any(self.tool_name_to_mcp_server_name_mapping.get(s) == server.name for s in spellings)

    async def _get_tools_from_server(self, server, **kwargs):
        self.list_calls.append((server.name, kwargs))
        if self._gate is not None:
            await self._gate.wait()
        if self._error is not None:
            raise self._error
        for tool in self._tools:
            self.tool_name_to_mcp_server_name_mapping[tool] = server.name
            self.tool_name_to_mcp_server_name_mapping[f"{server.name}-{tool}"] = server.name
        return [SimpleNamespace(name=f"{server.name}-{tool}") for tool in self._tools]


class FakeLogger:
    def __init__(self):
        self.warnings = []

    def warning(self, *args, **kwargs):
        self.warnings.append(args)


VL = SimpleNamespace(server_id="id-vl", name="victorialogs", alias="victorialogs")
VM = SimpleNamespace(server_id="id-vm", name="victoriametrics", alias="victoriametrics")


def _prepare_headers(**kwargs):
    return f"auth-for-{kwargs['server'].name}", {"x-extra": "1"}


@pytest.fixture
def mod():
    sys.modules.pop("middleware.mcp_tool_routing.mcp_tool_routing", None)
    return importlib.import_module("middleware.mcp_tool_routing.mcp_tool_routing")


def _wrapped(mod, manager, logger=None, prepare_headers=_prepare_headers):
    calls = []

    async def original(**kwargs):
        calls.append(dict(manager.tool_name_to_mcp_server_name_mapping))
        return "result"

    warmer = mod.McpToolMappingWarmer(
        manager, FakeUtils, prepare_headers, logger or FakeLogger())
    return mod.wrap_execute_mcp_tool(original, warmer), calls


def _call(name, servers=(VL, VM), **kwargs):
    return dict(name=name, arguments={}, allowed_mcp_servers=list(servers), start_time=None, **kwargs)


async def test_cold_server_is_listed_before_the_call(mod):
    manager = FakeManager()
    execute, calls = _wrapped(mod, manager)

    result = await execute(**_call("victorialogs-query"))

    assert result == "result"
    assert [name for name, _ in manager.list_calls] == ["victorialogs"]
    assert calls == [{"query": "victorialogs", "victorialogs-query": "victorialogs"}]


async def test_warm_server_is_not_listed(mod):
    manager = FakeManager()
    manager.tool_name_to_mcp_server_name_mapping["victorialogs-query"] = "victorialogs"
    execute, calls = _wrapped(mod, manager)

    await execute(**_call("victorialogs-query"))

    assert manager.list_calls == []
    assert len(calls) == 1


async def test_server_is_listed_when_the_requested_tool_is_unmapped(mod):
    manager = FakeManager(tools=("query", "hits"))
    manager.tool_name_to_mcp_server_name_mapping["victorialogs-query"] = "victorialogs"
    execute, _ = _wrapped(mod, manager)

    await execute(**_call("victorialogs-hits"))

    assert [name for name, _ in manager.list_calls] == ["victorialogs"]


async def test_another_warm_server_does_not_count_as_warm(mod):
    manager = FakeManager()
    manager.tool_name_to_mcp_server_name_mapping["victoriametrics-query"] = "victoriametrics"
    execute, _ = _wrapped(mod, manager)

    await execute(**_call("victorialogs-query"))

    assert [name for name, _ in manager.list_calls] == ["victorialogs"]


async def test_concurrent_cold_calls_list_once(mod):
    gate = asyncio.Event()
    manager = FakeManager(gate=gate)
    execute, calls = _wrapped(mod, manager)

    pending = asyncio.gather(
        execute(**_call("victorialogs-query")),
        execute(**_call("victorialogs-query")),
    )
    await asyncio.sleep(0)
    gate.set()
    assert await pending == ["result", "result"]

    assert len(manager.list_calls) == 1
    assert len(calls) == 2


async def test_callers_waiting_on_a_failed_listing_do_not_list_again(mod):
    gate = asyncio.Event()
    manager = FakeManager(gate=gate, error=RuntimeError("upstream down"))
    execute, calls = _wrapped(mod, manager)

    pending = asyncio.gather(*(execute(**_call("victorialogs-query")) for _ in range(3)))
    await asyncio.sleep(0)
    gate.set()
    assert await pending == ["result"] * 3

    assert len(manager.list_calls) == 1
    assert len(calls) == 3


async def test_a_later_call_retries_a_failed_listing(mod):
    manager = FakeManager(error=RuntimeError("upstream down"))
    execute, _ = _wrapped(mod, manager)

    await execute(**_call("victorialogs-query"))
    await execute(**_call("victorialogs-query"))

    assert len(manager.list_calls) == 2


async def test_list_failure_still_runs_the_call(mod):
    manager = FakeManager(error=RuntimeError("upstream down"))
    logger = FakeLogger()
    execute, calls = _wrapped(mod, manager, logger=logger)

    assert await execute(**_call("victorialogs-query")) == "result"

    assert len(calls) == 1
    assert logger.warnings


async def test_broken_litellm_internal_still_runs_the_call(mod):
    manager = FakeManager()
    manager._server_exposes_tool = None
    logger = FakeLogger()
    execute, calls = _wrapped(mod, manager, logger=logger)

    assert await execute(**_call("victorialogs-query")) == "result"

    assert len(calls) == 1
    assert logger.warnings


async def test_header_preparation_failure_still_runs_the_call(mod):
    def broken(**kwargs):
        raise ValueError("bad header")

    manager = FakeManager()
    execute, calls = _wrapped(mod, manager, prepare_headers=broken)

    assert await execute(**_call("victorialogs-query")) == "result"
    assert manager.list_calls == []
    assert len(calls) == 1


async def test_unknown_prefix_is_not_listed(mod):
    manager = FakeManager()
    execute, calls = _wrapped(mod, manager)

    await execute(**_call("github-search"))

    assert manager.list_calls == []
    assert len(calls) == 1


async def test_server_the_caller_cannot_reach_is_not_listed(mod):
    manager = FakeManager()
    execute, _ = _wrapped(mod, manager)

    await execute(**_call("victorialogs-query", servers=(VM,)))

    assert manager.list_calls == []


async def test_requested_server_id_warms_that_server_for_a_bare_name(mod):
    manager = FakeManager()
    execute, _ = _wrapped(mod, manager)

    await execute(**_call("query", requested_server_id="id-vl"))

    assert [name for name, _ in manager.list_calls] == ["victorialogs"]


async def test_listing_uses_the_callers_auth_context(mod):
    seen = {}

    def prepare_headers(**kwargs):
        seen.update(kwargs)
        return _prepare_headers(**kwargs)

    manager = FakeManager()
    execute, _ = _wrapped(mod, manager, prepare_headers=prepare_headers)
    user = object()

    await execute(**_call(
        "victorialogs-query",
        user_api_key_auth=user,
        mcp_auth_header="caller-token",
        mcp_server_auth_headers={"victorialogs": {"Authorization": "x"}},
        oauth2_headers={"o": "1"},
        raw_headers={"r": "1"},
    ))

    assert seen["server"] is VL
    assert seen["mcp_auth_header"] == "caller-token"
    assert seen["mcp_server_auth_headers"] == {"victorialogs": {"Authorization": "x"}}
    assert seen["oauth2_headers"] == {"o": "1"}
    assert seen["raw_headers"] == {"r": "1"}
    assert seen["user_api_key_auth"] is user
    _, list_kwargs = manager.list_calls[0]
    assert list_kwargs["mcp_auth_header"] == "auth-for-victorialogs"
    assert list_kwargs["extra_headers"] == {"x-extra": "1"}
    assert list_kwargs["raw_headers"] == {"r": "1"}
    assert list_kwargs["user_api_key_auth"] is user
    assert list_kwargs["oauth2_headers"] == {"o": "1"}


async def test_wrapper_passes_every_argument_through(mod):
    manager = FakeManager()
    manager.tool_name_to_mcp_server_name_mapping["victorialogs-query"] = "victorialogs"
    received = {}

    async def original(**kwargs):
        received.update(kwargs)
        return "result"

    warmer = mod.McpToolMappingWarmer(manager, FakeUtils, _prepare_headers, FakeLogger())
    execute = mod.wrap_execute_mcp_tool(original, warmer)
    call = _call("victorialogs-query", litellm_logging_obj="log", guardrail_context={"g": 1})

    await execute(**call)

    assert received == call


@pytest.fixture
def fake_litellm(monkeypatch):
    server = types.ModuleType("litellm.proxy._experimental.mcp_server.server")
    rest = types.ModuleType("litellm.proxy._experimental.mcp_server.rest_endpoints")
    manager_mod = types.ModuleType("litellm.proxy._experimental.mcp_server.mcp_server_manager")
    utils = types.ModuleType("litellm.proxy._experimental.mcp_server.utils")

    async def execute_mcp_tool(**kwargs):
        return "original"

    server.execute_mcp_tool = execute_mcp_tool
    server._prepare_mcp_server_headers = _prepare_headers
    rest.execute_mcp_tool = execute_mcp_tool
    manager_mod.global_mcp_server_manager = FakeManager()
    for attr in ("normalize_server_name", "iter_known_server_prefixes",
                 "match_known_server_prefix", "strip_known_server_prefix"):
        setattr(utils, attr, getattr(FakeUtils, attr))

    packages = {}
    for name in ("litellm", "litellm.proxy", "litellm.proxy._experimental", "litellm.proxy._experimental.mcp_server"):
        packages[name] = types.ModuleType(name)
        packages[name].__path__ = []
    modules = {
        **packages,
        server.__name__: server,
        rest.__name__: rest,
        manager_mod.__name__: manager_mod,
        utils.__name__: utils,
    }
    for name, module in modules.items():
        monkeypatch.setitem(sys.modules, name, module)
    return SimpleNamespace(
        server=server, rest=rest, utils=utils, manager=manager_mod.global_mcp_server_manager,
        original=execute_mcp_tool)


def test_install_wraps_both_call_paths_once(mod, fake_litellm):
    assert mod.install_mcp_tool_routing_patch() is True
    patched = fake_litellm.server.execute_mcp_tool

    assert patched is not fake_litellm.original
    assert fake_litellm.rest.execute_mcp_tool is patched

    assert mod.install_mcp_tool_routing_patch() is True
    assert fake_litellm.server.execute_mcp_tool is patched


async def test_installed_patch_warms_then_calls_original(mod, fake_litellm):
    mod.install_mcp_tool_routing_patch()
    manager = sys.modules[
        "litellm.proxy._experimental.mcp_server.mcp_server_manager"].global_mcp_server_manager

    result = await fake_litellm.server.execute_mcp_tool(**_call("victorialogs-query"))

    assert result == "original"
    assert manager.tool_name_to_mcp_server_name_mapping["victorialogs-query"] == "victorialogs"


@pytest.mark.parametrize("owner, attr", [
    ("server", "execute_mcp_tool"),
    ("server", "_prepare_mcp_server_headers"),
    ("manager", "_get_tools_from_server"),
    ("manager", "_server_exposes_tool"),
    ("utils", "normalize_server_name"),
    ("utils", "iter_known_server_prefixes"),
    ("utils", "match_known_server_prefix"),
    ("utils", "strip_known_server_prefix"),
])
def test_install_leaves_litellm_untouched_when_an_internal_is_missing(
        mod, fake_litellm, monkeypatch, caplog, owner, attr):
    target = getattr(fake_litellm, owner)
    monkeypatch.delattr(type(target) if owner == "manager" else target, attr)

    assert mod.install_mcp_tool_routing_patch() is False

    assert getattr(fake_litellm.server, "execute_mcp_tool", None) in (None, fake_litellm.original)
    assert fake_litellm.rest.execute_mcp_tool is fake_litellm.original
    assert attr in caplog.text


def test_install_leaves_litellm_untouched_when_a_module_is_missing(mod, fake_litellm, monkeypatch, caplog):
    monkeypatch.setitem(sys.modules, fake_litellm.rest.__name__, None)

    assert mod.install_mcp_tool_routing_patch() is False

    assert fake_litellm.server.execute_mcp_tool is fake_litellm.original
    assert "rest_endpoints" in caplog.text


def test_install_is_a_no_op_without_litellm(mod, monkeypatch):
    monkeypatch.setitem(sys.modules, "litellm", None)

    assert mod.install_mcp_tool_routing_patch() is False


def test_module_exposes_a_hookless_middleware(mod):
    middleware = mod.mcp_tool_routing

    assert not hasattr(middleware, "async_pre_call_hook")
