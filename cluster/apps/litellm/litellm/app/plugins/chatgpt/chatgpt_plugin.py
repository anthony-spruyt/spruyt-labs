import json
import os
from functools import lru_cache
from typing import Any

try:
    from .litellm_patch import install_litellm_patches
except ImportError:
    from litellm_patch import install_litellm_patches


install_litellm_patches()

_DEFAULT_CONFIG_PATH = "/app/config.yaml"

_CHATGPT_RESPONSES_MODELS = {
    "chatgpt/gpt-5.5",
    "chatgpt/responses/gpt-5.5",
    "chatgpt/gpt-5.4-mini",
    "chatgpt/responses/gpt-5.4-mini",
}


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


def _get_model_list_entry(config: dict, model: str) -> dict | None:
    model_list = config.get("model_list") or []
    if not isinstance(model_list, list):
        return None
    for entry in model_list:
        if isinstance(entry, dict) and entry.get("model_name") == model:
            return entry
    return None


def _resolve_model_list_entry(config: dict, model: str) -> str | None:
    entry = _get_model_list_entry(config, model)
    if not isinstance(entry, dict):
        return None
    litellm_params = entry.get("litellm_params") or {}
    target = litellm_params.get("model")
    return target if isinstance(target, str) else None


def _model_entry_num_retries(config: dict, model: str) -> int | None:
    entry = _get_model_list_entry(config, model)
    if not isinstance(entry, dict):
        return None
    litellm_params = entry.get("litellm_params") or {}
    num_retries = litellm_params.get("num_retries")
    return num_retries if isinstance(num_retries, int) else None


def _router_num_retries(config: dict) -> int | None:
    router_settings = config.get("router_settings") or {}
    if not isinstance(router_settings, dict):
        return None
    num_retries = router_settings.get("num_retries")
    return num_retries if isinstance(num_retries, int) else None


def _resolve_configured_chatgpt_model(model: Any) -> tuple[dict, str | None]:
    if not isinstance(model, str):
        return {}, None
    config = _load_config(_config_path())
    return config, _resolve_configured_model(model, config)


def _configured_chatgpt_num_retries(
    config: dict,
    model: str,
    resolved: str | None,
) -> int | None:
    if resolved not in _CHATGPT_RESPONSES_MODELS:
        return None

    current = model
    seen = set()
    while current not in seen:
        seen.add(current)
        configured = _model_entry_num_retries(config, current)
        if configured is not None:
            return configured
        target = _resolve_alias(config, current) or _resolve_model_list_entry(config, current)
        if not target:
            break
        current = target
    return _router_num_retries(config) or 2


def _resolve_configured_model(model: str, config: dict) -> str:
    current = model
    seen = set()
    while current not in seen:
        seen.add(current)
        target = _resolve_alias(config, current) or _resolve_model_list_entry(
            config, current)
        if not target:
            return current
        current = target
    return current


def _is_chatgpt_routed_model(model: Any) -> bool:
    if not isinstance(model, str):
        return False
    if model.startswith("chatgpt/"):
        return True
    resolved = _resolve_configured_model(model, _load_config(_config_path()))
    return resolved.startswith("chatgpt/")


def _system_to_developer_content(system: Any) -> str:
    if isinstance(system, str):
        return system
    if isinstance(system, list):
        parts = []
        for block in system:
            if isinstance(block, str):
                parts.append(block)
            elif isinstance(block, dict) and block.get("type") == "text":
                parts.append(str(block.get("text", "")))
        return "\n\n".join(part for part in parts if part)
    return str(system)


class ChatGPTMiddleware:
    async def async_pre_call_hook(
        self, user_api_key_dict, cache, data: dict, call_type: str,
    ) -> dict:
        model = data.get("model")
        if _is_chatgpt_routed_model(model):
            config, resolved_model = _resolve_configured_chatgpt_model(model)

            if isinstance(model, str):
                retry_count = _configured_chatgpt_num_retries(
                    config, model, resolved_model)
                if retry_count is not None and data.get("num_retries") is None:
                    data["num_retries"] = retry_count

            # Anthropic Messages format: top-level "system" field
            system_content = data.get("system")
            if system_content:
                messages = data.get("messages")
                if not isinstance(messages, list):
                    return data
                dev_msg = {
                    "role": "developer",
                    "content": _system_to_developer_content(system_content),
                }
                messages.insert(0, dev_msg)
                data["messages"] = messages
                data.pop("system", None)
            # Chat Completions format: role in messages/input
            for key in ("messages", "input"):
                items = data.get(key)
                if isinstance(items, list):
                    for msg in items:
                        if isinstance(msg, dict) and msg.get("role") == "system":
                            msg["role"] = "developer"
        return data

# Module-level instance consumed by custom_callbacks.middleware.registry.
chatgpt_middleware = ChatGPTMiddleware()
