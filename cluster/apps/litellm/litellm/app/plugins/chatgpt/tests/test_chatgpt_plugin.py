import importlib
import json
import os
import sys

import pytest


_HERE = os.path.dirname(__file__)
_PLUGIN_DIR = os.path.dirname(_HERE)
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)


@pytest.fixture
def plugin():
    if "chatgpt_plugin" in sys.modules:
        return importlib.reload(sys.modules["chatgpt_plugin"])
    return importlib.import_module("chatgpt_plugin")


async def test_anthropic_system_moves_to_developer(plugin):
    data = {
        "model": "chatgpt/gpt-5.5",
        "system": "Use terse answers.",
        "messages": [{"role": "user", "content": "hello"}],
    }

    out = await plugin.chatgpt_middleware.async_pre_call_hook(
        None, None, data, "anthropic_messages")

    assert "system" not in out
    assert out["messages"][0] == {"role": "developer", "content": "Use terse answers."}
    assert out["messages"][1]["role"] == "user"


async def test_anthropic_system_blocks_move_to_single_developer_message(plugin):
    data = {
        "model": "chatgpt/gpt-5.5",
        "system": [
            {"type": "text", "text": "cached prefix"},
            {"type": "text", "text": "<hindsight-memory>\nfact\n</hindsight-memory>"},
        ],
        "messages": [{"role": "user", "content": "hello"}],
    }

    out = await plugin.chatgpt_middleware.async_pre_call_hook(
        None, None, data, "anthropic_messages")

    assert "system" not in out
    assert out["messages"][0]["role"] == "developer"
    assert "cached prefix" in out["messages"][0]["content"]
    assert "<hindsight-memory>" in out["messages"][0]["content"]


async def test_system_roles_are_renamed_for_chatgpt_only(plugin):
    data = {
        "model": "chatgpt/gpt-5.5",
        "messages": [
            {"role": "system", "content": "sys"},
            {"role": "user", "content": "hello"},
        ],
    }

    out = await plugin.chatgpt_middleware.async_pre_call_hook(
        None, None, data, "completion")

    assert out["stream"] is True
    assert out["num_retries"] == 2
    assert out["messages"][0]["role"] == "developer"


async def test_configured_alias_to_gpt55_gets_retry_count(monkeypatch, tmp_path):
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps({
        "router_settings": {
            "num_retries": 5,
            "model_group_alias": {
                "claude-opus-4-7": "chatgpt/gpt-5.5",
                "claude-opus-4-8": "chatgpt/responses/gpt-5.5",
                "claude-haiku-4-5": "chatgpt/gpt-5.4-mini",
            },
        },
        "model_list": [
            {
                "model_name": "chatgpt/gpt-5.5",
                "litellm_params": {"model": "chatgpt/gpt-5.5", "num_retries": 4},
            },
            {
                "model_name": "chatgpt/responses/gpt-5.5",
                "litellm_params": {"model": "chatgpt/responses/gpt-5.5", "num_retries": 6},
            },
            {
                "model_name": "chatgpt/gpt-5.4-mini",
                "litellm_params": {"model": "chatgpt/responses/gpt-5.4-mini", "num_retries": 3},
            },
        ],
    }))
    monkeypatch.setenv("CHATGPT_CONFIG_PATH", str(config_path))
    sys.modules.pop("chatgpt_plugin", None)
    plugin = importlib.import_module("chatgpt_plugin")

    out = await plugin.chatgpt_middleware.async_pre_call_hook(
        None,
        None,
        {"model": "claude-opus-4-7", "messages": [{"role": "user", "content": "hello"}]},
        "completion",
    )
    responses_out = await plugin.chatgpt_middleware.async_pre_call_hook(
        None,
        None,
        {"model": "claude-opus-4-8", "messages": [{"role": "user", "content": "hello"}]},
        "completion",
    )
    mini_out = await plugin.chatgpt_middleware.async_pre_call_hook(
        None,
        None,
        {"model": "claude-haiku-4-5", "messages": [{"role": "user", "content": "hello"}]},
        "completion",
    )

    assert out["stream"] is True
    assert out["num_retries"] == 4
    assert responses_out["stream"] is True
    assert responses_out["num_retries"] == 6
    assert mini_out["stream"] is True
    assert mini_out["num_retries"] == 3


async def test_existing_num_retries_is_preserved(plugin):
    data = {
        "model": "chatgpt/gpt-5.5",
        "num_retries": 9,
        "messages": [{"role": "user", "content": "hello"}],
    }

    out = await plugin.chatgpt_middleware.async_pre_call_hook(
        None, None, data, "completion")

    assert out["stream"] is True
    assert out["num_retries"] == 9


async def test_configured_alias_to_chatgpt_is_renamed(monkeypatch, tmp_path):
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps({
        "router_settings": {
            "model_group_alias": {
                "claude-sonnet-4-6": "chatgpt/gpt-5.4",
            },
        },
        "model_list": [
            {
                "model_name": "chatgpt/gpt-5.4",
                "litellm_params": {"model": "chatgpt/gpt-5.4"},
            },
        ],
    }))
    monkeypatch.setenv("CHATGPT_CONFIG_PATH", str(config_path))
    sys.modules.pop("chatgpt_plugin", None)
    plugin = importlib.import_module("chatgpt_plugin")
    data = {
        "model": "claude-sonnet-4-6",
        "system": "alias system",
        "messages": [{"role": "user", "content": "hello"}],
    }

    out = await plugin.chatgpt_middleware.async_pre_call_hook(
        None, None, data, "anthropic_messages")

    assert "system" not in out
    assert out["messages"][0] == {"role": "developer", "content": "alias system"}


async def test_unconfigured_claude_model_is_untouched(plugin):
    data = {
        "model": "claude-opus-4-8",
        "system": "sys",
        "messages": [{"role": "user", "content": "hello"}],
    }

    out = await plugin.chatgpt_middleware.async_pre_call_hook(
        None, None, data, "anthropic_messages")

    assert out == data


async def test_non_chatgpt_models_are_untouched(plugin):
    data = {
        "model": "gpt-4o",
        "system": "sys",
        "messages": [{"role": "user", "content": "hello"}],
    }

    out = await plugin.chatgpt_middleware.async_pre_call_hook(
        None, None, data, "anthropic_messages")

    assert "num_retries" not in out
    assert out == data


async def test_non_string_model_is_untouched(plugin):
    data = {
        "model": None,
        "system": "sys",
        "messages": [{"role": "system", "content": "do not rewrite"}],
    }

    out = await plugin.chatgpt_middleware.async_pre_call_hook(
        None, None, data, "completion")

    assert out == data


async def test_bad_messages_shape_preserves_anthropic_system(plugin):
    data = {
        "model": "chatgpt/gpt-5.5",
        "system": "do not drop this",
        "messages": None,
    }

    out = await plugin.chatgpt_middleware.async_pre_call_hook(
        None, None, data, "anthropic_messages")

    assert out["system"] == "do not drop this"
    assert out["messages"] is None
