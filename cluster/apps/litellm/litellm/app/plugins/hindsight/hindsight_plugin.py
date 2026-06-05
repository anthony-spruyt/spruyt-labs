"""Transparent proxy-side long-term memory for LiteLLM <-> Hindsight.

A ``CustomLogger`` callback that runs inside the LiteLLM proxy pod. It does NOT
require any change to the calling client (e.g. Claude Code CLI):

* ``async_pre_call_hook``  — RECALL relevant memories for the request's bank from
  Hindsight and inject them into the system prompt before the LLM call.
* ``async_log_success_event`` — RETAIN the user prompt + assistant response back
  into Hindsight (best effort, fire-and-forget ``async:true``).

bank_id resolution (per request, first match wins):
  1. request header ``X-Hindsight-Bank``
  2. virtual-key metadata ``hindsight_bank``
  3. team metadata ``hindsight_bank``
  4. none -> SKIP memory entirely (no shared default bank; avoids cross-repo
     memory contamination).

Both paths FAIL OPEN: any error/timeout is logged and swallowed so memory never
degrades or blocks the primary completion path.
"""

from __future__ import annotations

import os
import re
from typing import Any, Optional

import httpx

from litellm.integrations.custom_logger import CustomLogger
from litellm._logging import verbose_proxy_logger

# Wraps injected memory so we can strip a prior block before re-injecting
# (idempotency across retries) and so the model can recognize the provenance.
_MARKER_OPEN = "<hindsight-memory>"
_MARKER_CLOSE = "</hindsight-memory>"
_MARKER_RE = re.compile(
    re.escape(_MARKER_OPEN) + r".*?" + re.escape(_MARKER_CLOSE),
    re.DOTALL,
)

# Anthropic Messages API arrives with this litellm call_type. Everything else
# (completion/acompletion/...) is treated as OpenAI chat shape.
_ANTHROPIC_CALL_TYPES = {"anthropic_messages"}

_BANK_SANITIZE_RE = re.compile(r"[^A-Za-z0-9-]")


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


class HindsightMiddleware(CustomLogger):
    def __init__(self) -> None:
        super().__init__()
        self.base_url = os.getenv(
            "HINDSIGHT_BASE_URL",
            "http://hindsight-api.hindsight.svc.cluster.local:8888",
        ).rstrip("/")
        self.timeout_s = float(os.getenv("HINDSIGHT_TIMEOUT_S", "3.0"))
        self.recall_budget = os.getenv("HINDSIGHT_RECALL_BUDGET", "mid")
        self.max_memory_tokens = int(os.getenv("HINDSIGHT_MAX_MEMORY_TOKENS", "4096"))
        self.inject = _env_bool("HINDSIGHT_INJECT", True)
        self.retain = _env_bool("HINDSIGHT_RETAIN", True)
        self.bank_header = os.getenv("HINDSIGHT_BANK_HEADER", "x-hindsight-bank").lower()
        self.project = "default"

    # ------------------------------------------------------------------ #
    # Bank resolution
    # ------------------------------------------------------------------ #
    def _sanitize_bank(self, value: Any) -> Optional[str]:
        if not value or not isinstance(value, str):
            return None
        cleaned = _BANK_SANITIZE_RE.sub("", value.strip())
        return cleaned or None

    def _bank_from_headers(self, headers: Any) -> Optional[str]:
        if not isinstance(headers, dict):
            return None
        # headers may arrive with mixed case; normalize keys to lowercase.
        for key, val in headers.items():
            if isinstance(key, str) and key.lower() == self.bank_header:
                return self._sanitize_bank(val)
        return None

    def _resolve_bank(self, data: dict, user_api_key_dict: Any) -> Optional[str]:
        # (1) request header
        headers = (data.get("proxy_server_request") or {}).get("headers")
        bank = self._bank_from_headers(headers)
        if bank:
            return bank

        # (2) virtual-key metadata, (3) team metadata
        meta = getattr(user_api_key_dict, "metadata", None) or {}
        if isinstance(meta, dict):
            bank = self._sanitize_bank(meta.get("hindsight_bank"))
            if bank:
                return bank
            team_meta = meta.get("team_metadata") or meta.get("team_member_info") or {}
            if isinstance(team_meta, dict):
                bank = self._sanitize_bank(team_meta.get("hindsight_bank"))
                if bank:
                    return bank
        return None

    # ------------------------------------------------------------------ #
    # Message helpers
    # ------------------------------------------------------------------ #
    @staticmethod
    def _content_to_text(content: Any) -> str:
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            parts = []
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    parts.append(block.get("text", ""))
                elif isinstance(block, str):
                    parts.append(block)
            return "\n".join(p for p in parts if p)
        return ""

    def _latest_user_text(self, data: dict) -> str:
        for msg in reversed(data.get("messages", []) or []):
            if isinstance(msg, dict) and msg.get("role") == "user":
                return self._content_to_text(msg.get("content"))
        return ""

    @staticmethod
    def _strip_marker(text: str) -> str:
        return _MARKER_RE.sub("", text).rstrip()

    def _wrap(self, memory_text: str) -> str:
        return f"{_MARKER_OPEN}\n{memory_text}\n{_MARKER_CLOSE}"

    # ------------------------------------------------------------------ #
    # Injection — Anthropic str/blocks, OpenAI system message
    # ------------------------------------------------------------------ #
    def _inject_memory(self, data: dict, call_type: str, memory_text: str) -> dict:
        wrapped = self._wrap(memory_text)

        if call_type in _ANTHROPIC_CALL_TYPES:
            system = data.get("system")
            if system is None:
                data["system"] = wrapped
            elif isinstance(system, str):
                data["system"] = f"{self._strip_marker(system)}\n\n{wrapped}".strip()
            elif isinstance(system, list):
                # Preserve the cached prefix: drop any prior memory block, then
                # append the fresh memory as the LAST block.
                blocks = [
                    b for b in system
                    if not (isinstance(b, dict)
                            and b.get("type") == "text"
                            and _MARKER_OPEN in str(b.get("text", "")))
                ]
                blocks.append({"type": "text", "text": wrapped})
                data["system"] = blocks
            else:
                data["system"] = wrapped
            return data

        # OpenAI chat shape — system lives as messages[0] role=system.
        messages = data.get("messages") or []
        if messages and isinstance(messages[0], dict) and messages[0].get("role") == "system":
            existing = self._content_to_text(messages[0].get("content"))
            messages[0]["content"] = f"{self._strip_marker(existing)}\n\n{wrapped}".strip()
        else:
            messages.insert(0, {"role": "system", "content": wrapped})
        data["messages"] = messages
        return data

    # ------------------------------------------------------------------ #
    # Hindsight HTTP — recall / retain
    # ------------------------------------------------------------------ #
    def _recall_url(self, bank: str) -> str:
        return f"{self.base_url}/v1/{self.project}/banks/{bank}/memories/recall"

    def _memories_url(self, bank: str) -> str:
        return f"{self.base_url}/v1/{self.project}/banks/{bank}/memories"

    async def _recall(self, bank: str, query: str) -> str:
        body = {
            "query": query,
            "budget": self.recall_budget,
            "max_tokens": self.max_memory_tokens,
        }
        async with httpx.AsyncClient(timeout=self.timeout_s) as client:
            resp = await client.post(self._recall_url(bank), json=body)
            resp.raise_for_status()
            payload = resp.json()
        results = payload.get("results") or []
        texts = [r.get("text", "") for r in results if isinstance(r, dict) and r.get("text")]
        return "\n\n".join(texts).strip()

    # ------------------------------------------------------------------ #
    # Pre-call hook — RECALL + inject (fail open)
    # ------------------------------------------------------------------ #
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        if not self.inject:
            return data
        try:
            bank = self._resolve_bank(data, user_api_key_dict)
            if not bank:
                return data  # unknown traffic — never touch a shared bank
            query = self._latest_user_text(data)
            if not query:
                return data
            memory_text = await self._recall(bank, query)
            if memory_text:
                self._inject_memory(data, call_type, memory_text)
                verbose_proxy_logger.debug(
                    "hindsight: injected memory for bank=%s (%d chars)",
                    bank, len(memory_text),
                )
        except Exception as exc:  # noqa: BLE001 — fail open by design
            verbose_proxy_logger.warning("hindsight recall failed (fail-open): %s", exc)
        return data

    # ------------------------------------------------------------------ #
    # Success hook — RETAIN (swallow all)
    # ------------------------------------------------------------------ #
    @staticmethod
    def _response_text(response_obj: Any) -> str:
        try:
            choices = getattr(response_obj, "choices", None)
            if choices is None and isinstance(response_obj, dict):
                choices = response_obj.get("choices")
            if not choices:
                return ""
            first = choices[0]
            message = getattr(first, "message", None)
            if message is None and isinstance(first, dict):
                message = first.get("message")
            content = getattr(message, "content", None)
            if content is None and isinstance(message, dict):
                content = message.get("content")
            return content if isinstance(content, str) else ""
        except Exception:  # noqa: BLE001
            return ""

    def _resolve_bank_from_kwargs(self, kwargs: dict) -> Optional[str]:
        headers = (kwargs.get("proxy_server_request") or {}).get("headers")
        bank = self._bank_from_headers(headers)
        if bank:
            return bank
        meta = kwargs.get("litellm_params", {}).get("metadata") or kwargs.get("metadata") or {}
        if isinstance(meta, dict):
            bank = self._sanitize_bank(meta.get("hindsight_bank"))
            if bank:
                return bank
        return None

    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        if not self.retain:
            return
        try:
            bank = self._resolve_bank_from_kwargs(kwargs)
            if not bank:
                return
            user_text = self._latest_user_text(kwargs)
            assistant_text = self._response_text(response_obj)
            items = []
            if user_text:
                items.append({"content": user_text, "context": {"role": "user"}})
            if assistant_text:
                items.append({"content": assistant_text, "context": {"role": "assistant"}})
            if not items:
                return
            body = {"items": items, "async": True}
            async with httpx.AsyncClient(timeout=self.timeout_s) as client:
                resp = await client.post(self._memories_url(bank), json=body)
                resp.raise_for_status()
            verbose_proxy_logger.debug(
                "hindsight: retained %d item(s) for bank=%s", len(items), bank)
        except Exception as exc:  # noqa: BLE001 — never raise into the success path
            verbose_proxy_logger.warning("hindsight retain failed (swallowed): %s", exc)


# Module-level instance referenced by litellm_settings.callbacks as
# custom_callbacks.hindsight.hindsight_plugin.hindsight_middleware
hindsight_middleware = HindsightMiddleware()
