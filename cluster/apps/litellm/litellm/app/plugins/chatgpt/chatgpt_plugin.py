from typing import Literal, Optional, Union
from litellm.caching.caching import DualCache
from litellm.integrations.custom_logger import CustomLogger
from litellm.proxy._types import UserAPIKeyAuth

class ChatGPTMiddleware(CustomLogger):
    async def async_pre_call_hook(
        self, user_api_key_dict: UserAPIKeyAuth, cache: DualCache,
        data: dict, call_type: Literal["completion", "text_completion",
        "embeddings", "image_generation", "moderation", "audio_transcription",
        "pass_through_endpoint", "rerank", "mcp_call", "anthropic_messages"],
    ) -> Optional[Union[Exception, str, dict]]:
        model = data.get("model", "")
        if model.startswith("chatgpt/"):
            # Anthropic Messages format: top-level "system" field
            system_content = data.pop("system", None)
            if system_content:
                dev_msg = {"role": "developer", "content": system_content}
                messages = data.get("messages", [])
                messages.insert(0, dev_msg)
                data["messages"] = messages
            # Chat Completions format: role in messages/input
            for key in ("messages", "input"):
                items = data.get(key)
                if isinstance(items, list):
                    for msg in items:
                        if isinstance(msg, dict) and msg.get("role") == "system":
                            msg["role"] = "developer"
        return data

# Module-level instance referenced by litellm_settings.callbacks as
# custom_callbacks.chatgpt.chatgpt_plugin.chatgpt_middleware
chatgpt_middleware = ChatGPTMiddleware()
