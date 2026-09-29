"""Swap credentials for same-shape fakes before the model sees them, and back in the reply."""

from __future__ import annotations

import codecs
import copy
import hashlib
import hmac
import json
import os
import re
import string
import time
from collections import OrderedDict
from typing import Any, Optional

from litellm._logging import verbose_proxy_logger


_URLSAFE_20 = r"[A-Za-z0-9_\-]{20,}"

# (prefix, body, suffix). Only the body is replaced; the prefix keeps the fake recognisable.
_PATTERNS: tuple[tuple[str, str, Optional[str]], ...] = (
    (r"sl_", r"[A-Za-z0-9]{29,}", None),
    (r"sk-ant-[a-z]+\d{2}-", r"[A-Za-z0-9_\-]{32,}", None),
    (r"sk-or-v1-", r"[a-f0-9]{64}(?![A-Za-z0-9])", None),
    (r"sk-(?:proj|svcacct|admin)-", _URLSAFE_20, None),
    (r"sk-", _URLSAFE_20, None),
    (r"github_pat_", r"[A-Za-z0-9_]{22,}", None),
    (r"gh[pousr]_", r"[A-Za-z0-9]{36,}", None),
    (r"glpat-", _URLSAFE_20, None),
    (r"AIza", r"[A-Za-z0-9_\-]{35}(?![A-Za-z0-9_\-])", None),
    (r"GOCSPX-", r"[A-Za-z0-9_\-]{28}(?![A-Za-z0-9_\-])", None),
    (r"ya29\.", _URLSAFE_20, None),
    (r"(?:AKIA|ASIA)", r"[A-Z0-9]{16}(?![A-Za-z0-9])", None),
    (r"xox[abprs]-", r"[A-Za-z0-9\-]{10,}", None),
    (r"(?:sk|rk)_(?:live|test)_", r"[A-Za-z0-9]{16,}", None),
    (r"hf_", r"[A-Za-z0-9]{30,}", None),
    (r"npm_", r"[A-Za-z0-9]{36}(?![A-Za-z0-9])", None),
    (r"pypi-", r"[A-Za-z0-9_\-]{50,}", None),
    (r"tskey-[a-z]+-", r"[A-Za-z0-9\-]{20,}", None),
    (r"AGE-SECRET-KEY-1", r"[0-9A-Z]{58}", None),
    (r"eyJ", r"[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}", None),
    (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", r"(?:(?!-----BEGIN )[\s\S]){16,16384}?", r"-----END [A-Z ]*PRIVATE KEY-----"),
)


def _compile_patterns() -> re.Pattern:
    parts = []
    for i, (prefix, body, suffix) in enumerate(_PATTERNS):
        part = f"(?P<p{i}>{prefix})(?P<b{i}>{body})"
        if suffix:
            part += f"(?P<s{i}>{suffix})"
        parts.append(part)
    return re.compile(r"(?<![A-Za-z0-9_])(?:" + "|".join(parts) + ")")


_SECRET_RE = _compile_patterns()
_OPAQUE_BLOCK_TYPES = frozenset({"thinking", "redacted_thinking", "base64"})
_MASKED_FIELDS = ("system", "messages")
_SUPPORTED_CALL_TYPES = frozenset({"anthropic_messages", "acompletion", "completion"})
_STREAM_DELTA_FIELDS = {"text_delta": "text", "input_json_delta": "partial_json"}
_HEX_BODY = frozenset("0123456789abcdef")


def _looks_random(body: str) -> bool:
    return any(c.isdigit() or c.isupper() for c in body)


def _json_escape(value: str) -> str:
    return json.dumps(value)[1:-1]


class _CallState:
    def __init__(self) -> None:
        self.created = time.monotonic()
        self.fakes: dict[str, str] = {}
        self._pattern: Optional[re.Pattern] = None

    def pattern(self) -> re.Pattern:
        if self._pattern is None:
            keys = sorted(self.fakes, key=len, reverse=True)
            self._pattern = re.compile("|".join(re.escape(k) for k in keys))
        return self._pattern

    def restore(self, text: str) -> str:
        if not text:
            return text
        return self.pattern().sub(lambda m: self.fakes[m.group(0)], text)

    def held_suffix_len(self, text: str) -> int:
        best = 0
        for fake in self.fakes:
            start = max(0, len(text) - len(fake) + 1)
            i = text.find(fake[0], start)
            while i != -1:
                if fake.startswith(text[i:]):
                    best = max(best, len(text) - i)
                    break
                i = text.find(fake[0], i + 1)
        return best


class _Holdback:
    """Restores streamed text, holding back any tail that could be the start of a split fake."""

    def __init__(self, state: _CallState) -> None:
        self.state = state
        self.held: dict[Any, str] = {}

    def feed(self, key: Any, text: str) -> str:
        buf = self.state.restore(self.held.pop(key, "") + text)
        keep = self.state.held_suffix_len(buf)
        if keep:
            self.held[key] = buf[-keep:]
            return buf[:-keep]
        return buf

    def flush(self, key: Any) -> str:
        return self.state.restore(self.held.pop(key, ""))


class SecretMaskingMiddleware:
    def __init__(self, key: bytes, ttl_seconds: float = 3600.0) -> None:
        self._key = key
        self._ttl = ttl_seconds
        self._calls: OrderedDict[str, _CallState] = OrderedDict()

    def pending_calls(self) -> int:
        return len(self._calls)

    # async_* names mirror LiteLLM's CustomLogger hooks; callers await them.
    async def async_pre_call_hook(self, _user_api_key_dict, _cache, data: dict, call_type: str):  # NOSONAR
        call_id = data.get("litellm_call_id")
        if call_type not in _SUPPORTED_CALL_TYPES or not call_id:
            return data

        state = _CallState()
        masked = {}
        for field in _MASKED_FIELDS:
            if field in data:
                value = self._mask_value(data[field], state)
                if value is not data[field]:
                    masked[field] = value
        if not state.fakes:
            return data

        data.update(masked)
        self._prune()
        self._calls[call_id] = state
        return data

    async def async_post_call_success_hook(self, data: dict, response, **_):  # NOSONAR
        state = self._calls.pop((data or {}).get("litellm_call_id"), None)
        if state is None:
            return None
        if isinstance(response, dict):
            return _restore_value(response, state)
        return _restore_chat_response(response, state)

    async def async_post_call_failure_hook(self, request_data: dict, **_) -> None:  # NOSONAR
        self._calls.pop((request_data or {}).get("litellm_call_id"), None)

    async def async_post_call_streaming_iterator_hook(self, response, request_data: dict, **_):
        call_id = (request_data or {}).get("litellm_call_id")
        state = self._calls.get(call_id)
        stream = response if state is None else _restore_stream(response, _StreamRestorer(state))
        try:
            async for chunk in stream:
                yield chunk
        finally:
            self._calls.pop(call_id, None)

    def _prune(self) -> None:
        cutoff = time.monotonic() - self._ttl
        while self._calls:
            oldest = next(iter(self._calls.values()))
            if oldest.created >= cutoff:
                break
            self._calls.popitem(last=False)

    def _mask_value(self, value: Any, state: _CallState) -> Any:
        if isinstance(value, str):
            return self._mask_text(value, state)
        if isinstance(value, list):
            out = [self._mask_value(item, state) for item in value]
            return out if any(a is not b for a, b in zip(out, value)) else value
        if isinstance(value, dict):
            if value.get("type") in _OPAQUE_BLOCK_TYPES:
                return value
            out = {k: self._mask_value(v, state) for k, v in value.items()}
            return out if any(out[k] is not value[k] for k in value) else value
        return value

    def _mask_text(self, text: str, state: _CallState) -> str:
        def replace(match: re.Match) -> str:
            i = next(n for n in range(len(_PATTERNS)) if match.group(f"p{n}") is not None)
            prefix = match.group(f"p{i}")
            body = match.group(f"b{i}")
            suffix = match.group(f"s{i}") if _PATTERNS[i][2] else ""
            if not _looks_random(body):
                return match.group(0)
            return self._fake_for(match.group(0), len(prefix), len(suffix), state)

        out = _SECRET_RE.sub(replace, text)
        return text if out == text else out

    def _fake_for(self, found: str, prefix_len: int, suffix_len: int, state: _CallState) -> str:
        real = found
        escaped = False
        if "\\" in found:
            try:
                real = json.loads(f'"{found}"')
                escaped = True
            except ValueError:
                pass

        fake = self._fake(real, prefix_len, suffix_len)
        if fake == real:
            return found
        state.fakes[fake] = real
        escaped_fake = _json_escape(fake)
        if escaped_fake != fake:
            state.fakes[escaped_fake] = _json_escape(real)
        return escaped_fake if escaped else fake

    def _fake(self, real: str, prefix_len: int, suffix_len: int) -> str:
        end = len(real) - suffix_len
        body = real[prefix_len:end]
        lower = "abcdef" if set(body) <= _HEX_BODY else string.ascii_lowercase
        rand = self._random_bytes(real)
        out = []
        in_escape = False
        for ch in body:
            if in_escape:
                in_escape = False
                out.append(ch)
            elif ch == "\\":
                in_escape = True
                out.append(ch)
            elif ch in string.digits:
                out.append(string.digits[next(rand) % 10])
            elif ch in string.ascii_lowercase:
                out.append(lower[next(rand) % len(lower)])
            elif ch in string.ascii_uppercase:
                out.append(string.ascii_uppercase[next(rand) % 26])
            else:
                out.append(ch)
        return real[:prefix_len] + "".join(out) + real[end:]

    def _random_bytes(self, real: str):
        seed = real.encode()
        counter = 0
        while True:
            block = hmac.new(self._key, seed + counter.to_bytes(4, "big"), hashlib.sha256).digest()
            yield from block
            counter += 1


async def _restore_stream(response, restorer: _StreamRestorer):
    async for chunk in response:
        try:
            out = restorer.process(chunk)
        except Exception as exc:  # noqa: BLE001 - a restore bug must not kill the stream
            _log_warning("secret masking stream restore failed open: %s", type(exc).__name__)
            out = None
        if out is None:
            for pending in restorer.finish():
                yield pending
            yield chunk
            break
        for item in out:
            yield item
    else:
        for pending in restorer.finish():
            yield pending
        return
    async for rest in response:
        yield rest


def _restore_value(value: Any, state: _CallState) -> Any:
    if isinstance(value, str):
        return state.restore(value)
    if isinstance(value, list):
        out = [_restore_value(item, state) for item in value]
        return out if any(a is not b and a != b for a, b in zip(out, value)) else value
    if isinstance(value, dict):
        if value.get("type") in _OPAQUE_BLOCK_TYPES:
            return value
        out = {k: _restore_value(v, state) for k, v in value.items()}
        return out if any(out[k] != value[k] for k in value) else value
    return value


def _restore_chat_response(response: Any, state: _CallState) -> Any:
    choices = getattr(response, "choices", None)
    if not choices:
        return None
    restored = copy.deepcopy(response)
    for choice in restored.choices:
        message = getattr(choice, "message", None)
        if message is None:
            continue
        if isinstance(getattr(message, "content", None), str):
            message.content = state.restore(message.content)
        for call in getattr(message, "tool_calls", None) or ():
            function = getattr(call, "function", None)
            if function is not None and isinstance(function.arguments, str):
                function.arguments = state.restore(function.arguments)
    return restored


class _StreamRestorer:
    def __init__(self, state: _CallState) -> None:
        self.hold = _Holdback(state)
        self.delta_types: dict[int, str] = {}
        self.sse_buffer = ""
        self.mode: Optional[str] = None
        self.decoder = codecs.getincrementaldecoder("utf-8")()
        self.last_chat_chunk: Any = None
        self.tool_templates: dict[tuple, Any] = {}

    def process(self, chunk: Any) -> list:
        if isinstance(chunk, (bytes, bytearray)):
            self.mode = "bytes"
            return self._sse(self.decoder.decode(bytes(chunk)))
        if isinstance(chunk, str):
            self.mode = "str"
            return self._sse(chunk)
        if isinstance(chunk, dict):
            self.mode = "dict"
            return self._events(chunk)
        if getattr(chunk, "choices", None) is not None:
            return [self._chat(chunk)]
        return [chunk]

    def finish(self) -> list:
        pending = self._flush_all_events()
        if self.mode == "dict":
            return pending
        if self.mode in ("bytes", "str"):
            text = self.sse_buffer + self.decoder.decode(b"", final=True) + self._format(pending)
            self.sse_buffer = ""
            if not text:
                return []
            return [text.encode() if self.mode == "bytes" else text]
        if self.last_chat_chunk is not None and self.hold.held:
            return [self._chat_flush(copy.deepcopy(self.last_chat_chunk))]
        return []

    def _sse(self, text: str) -> list:
        self.sse_buffer += text.replace("\r\n", "\n")
        *blocks, self.sse_buffer = self.sse_buffer.split("\n\n")
        pieces = []
        for block in blocks:
            event = _parse_sse_data(block)
            if event is None:
                pieces.append(block + "\n\n")
                continue
            events = self._events(event)
            if len(events) == 1 and events[0] is event:
                pieces.append(block + "\n\n")
            else:
                pieces.append(self._format(events))
        joined = "".join(pieces)
        if not joined:
            return []
        return [joined.encode()] if self.mode == "bytes" else [joined]

    @staticmethod
    def _format(events: list) -> str:
        return "".join(
            f"event: {e.get('type', 'message')}\ndata: {json.dumps(e)}\n\n" for e in events
        )

    def _events(self, event: dict) -> list:
        kind = event.get("type")
        index = event.get("index")
        if kind == "content_block_delta" and isinstance(index, int):
            delta = event.get("delta") or {}
            field = _STREAM_DELTA_FIELDS.get(delta.get("type"))
            if field is None or not isinstance(delta.get(field), str):
                return [event]
            self.delta_types[index] = delta["type"]
            text = self.hold.feed(index, delta[field])
            if text == delta[field]:
                return [event]
            if not text:
                return []
            return [{**event, "delta": {**delta, field: text}}]
        if kind == "content_block_stop" and index in self.hold.held:
            return [self._flush_event(index), event]
        if kind in ("message_delta", "message_stop"):
            return [*self._flush_all_events(), event]
        return [event]

    def _flush_all_events(self) -> list:
        # Copy the keys first; _flush_event pops from hold.held.
        indices = [k for k in self.hold.held if isinstance(k, int)]
        return [self._flush_event(i) for i in indices]

    def _flush_event(self, index: int) -> dict:
        delta_type = self.delta_types.get(index, "text_delta")
        return {
            "type": "content_block_delta",
            "index": index,
            "delta": {"type": delta_type, _STREAM_DELTA_FIELDS[delta_type]: self.hold.flush(index)},
        }

    def _chat(self, chunk: Any) -> Any:
        self.last_chat_chunk = chunk
        out = chunk
        for n, choice in enumerate(chunk.choices):
            delta = getattr(choice, "delta", None)
            if delta is not None:
                out = self._chat_choice(chunk, out, n, choice, delta)
        return out

    def _chat_choice(self, chunk: Any, out: Any, n: int, choice: Any, delta: Any) -> Any:
        content = getattr(delta, "content", None)
        if isinstance(content, str):
            text = self.hold.feed(("content", choice.index), content)
            if text != content:
                out = _own(chunk, out)
                out.choices[n].delta.content = text
        for t, call in enumerate(getattr(delta, "tool_calls", None) or ()):
            args = getattr(getattr(call, "function", None), "arguments", None)
            if not isinstance(args, str):
                continue
            key = ("tool", choice.index, call.index)
            self.tool_templates[key] = call
            text = self.hold.feed(key, args)
            if text != args:
                out = _own(chunk, out)
                out.choices[n].delta.tool_calls[t].function.arguments = text
        if getattr(choice, "finish_reason", None) and self._holds_for(choice.index):
            out = _own(chunk, out)
            self._chat_flush_choice(out.choices[n])
        return out

    def _holds_for(self, choice_index: int) -> bool:
        return any(isinstance(k, tuple) and k[1] == choice_index for k in self.hold.held)

    def _chat_flush(self, chunk: Any) -> Any:
        for choice in chunk.choices:
            choice.finish_reason = None
            self._chat_flush_choice(choice)
        return chunk

    def _chat_flush_choice(self, choice: Any) -> None:
        tail = self.hold.flush(("content", choice.index))
        if tail:
            choice.delta.content = (getattr(choice.delta, "content", None) or "") + tail
        calls = []
        for key in [k for k in self.hold.held if isinstance(k, tuple) and k[0] == "tool" and k[1] == choice.index]:
            call = copy.deepcopy(self.tool_templates[key])
            call.id = None
            call.function.name = None
            call.function.arguments = self.hold.flush(key)
            calls.append(call)
        if calls:
            choice.delta.tool_calls = calls


def _own(chunk: Any, out: Any) -> Any:
    return copy.deepcopy(chunk) if out is chunk else out


def _parse_sse_data(block: str) -> Optional[dict]:
    for line in block.split("\n"):
        if line.startswith("data:"):
            try:
                event = json.loads(line[5:].strip())
            except ValueError:
                return None
            return event if isinstance(event, dict) else None
    return None


def _log_warning(message: str, *args: Any) -> None:
    try:
        verbose_proxy_logger.warning(message, *args)
    except Exception:  # noqa: BLE001 - logging should never affect request handling
        return


def _key_from_env() -> bytes:
    salt = os.environ.get("LITELLM_SALT_KEY")
    if not salt:
        return os.urandom(32)
    return hmac.new(salt.encode(), b"litellm-secret-masking", hashlib.sha256).digest()


secret_masking = SecretMaskingMiddleware(key=_key_from_env())
