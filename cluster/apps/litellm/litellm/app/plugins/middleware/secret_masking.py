"""Swap credentials for same-shape fakes before the model sees them, and back in the reply."""

from __future__ import annotations

import bisect
import codecs
import copy
import hashlib
import hmac
import json
import os
import re
import string
import sys
import time
from collections import OrderedDict
from typing import Any, Callable, Optional

try:
    from .pipeline import MiddlewarePipeline
    from .shared_fakes import SharedFakes, shared_from_env
except ImportError:
    from pipeline import MiddlewarePipeline
    from shared_fakes import SharedFakes, shared_from_env


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
    (
        r"-----BEGIN [A-Z ]*PRIVATE KEY(?: BLOCK)?-----",
        r"(?:(?!-----BEGIN )[\s\S]){16,16384}?",
        r"-----END [A-Z ]*PRIVATE KEY(?: BLOCK)?-----",
    ),
)


def _compile_patterns() -> re.Pattern:
    parts = []
    for i, (prefix, body, suffix) in enumerate(_PATTERNS):
        part = f"(?P<p{i}>{prefix})(?P<b{i}>{body})"
        if suffix:
            part += f"(?P<s{i}>{suffix})"
        parts.append(part)
    # A JSON escape like \n ends in a letter, so it is allowed as a boundary.
    boundary = r"(?:(?<![A-Za-z0-9_])|(?<=\\[nrtbf])|(?<=\\u[0-9A-Fa-f]{4}))"
    return re.compile(boundary + "(?:" + "|".join(parts) + ")")


_SECRET_RE = _compile_patterns()
_log_warning = MiddlewarePipeline._log_warning
_OPAQUE_BLOCK_TYPES = frozenset({"thinking", "redacted_thinking", "reasoning", "base64", "input_audio"})
# Only the media-source fields: presigned URLs carry credentials, and rewriting them breaks the fetch.
_OPAQUE_FIELDS = {
    "image_url": ("image_url",),
    "file": ("file",),
    "input_image": ("image_url",),
    "input_file": ("file_url", "file_data"),
    "url": ("url",),
}
# Gemini parts carry no "type", so their binary payloads and signatures are recognised by key.
_GEMINI_OPAQUE_PART_KEYS = frozenset(
    {"inlineData", "inline_data", "fileData", "file_data", "thoughtSignature", "thought_signature"})
_GEMINI_SYSTEM_KEYS = ("systemInstruction", "system_instruction")
_GEMINI_FIELDS = ("contents", *_GEMINI_SYSTEM_KEYS, "config")
_MASKED_FIELDS = {
    "anthropic_messages": ("system", "messages"),
    "acompletion": ("messages",),
    "completion": ("messages",),
    "aresponses": ("instructions", "input"),
    "responses": ("instructions", "input"),
    "acompact_responses": ("instructions", "input"),
    "atext_completion": ("prompt",),
    "text_completion": ("prompt",),
    "agenerate_content": _GEMINI_FIELDS,
    "agenerate_content_stream": _GEMINI_FIELDS,
    "_aresponses_websocket": ("first_message",),
}
# LiteLLM runs no post-call hook for websocket replies, so there is nothing to release the call state.
_NO_REPLY_HOOKS = frozenset({"_aresponses_websocket"})
_TOKEN_COUNT_FIELDS = frozenset({"messages", "contents", "tools", "system"})
_STREAM_DELTA_FIELDS = {"text_delta": "text", "input_json_delta": "partial_json"}
# Responses API: delta event -> (done event, field on the done event holding the full text).
_RESPONSES_DELTAS = {
    "response.output_text.delta": ("response.output_text.done", "text"),
    "response.refusal.delta": ("response.refusal.done", "refusal"),
    "response.function_call_arguments.delta": ("response.function_call_arguments.done", "arguments"),
    "response.custom_tool_call_input.delta": ("response.custom_tool_call_input.done", "input"),
}
_RESPONSES_DONE = {done: (delta, field) for delta, (done, field) in _RESPONSES_DELTAS.items()}
_RESPONSES_TERMINAL = frozenset({"response.completed", "response.incomplete", "response.failed"})
_RESPONSES_TEXT_PARTS = frozenset({"output_text", "refusal"})
_HEX_BODY = frozenset("0123456789abcdef")
_DATA_URL_RE = re.compile(r"data:[^\s,]*;base64,")


def _looks_random(body: str) -> bool:
    return any(c.isdigit() or c.isupper() for c in body)


def _json_escape(value: str) -> str:
    return json.dumps(value)[1:-1]


_NEVER = re.compile(r"\b\B")


class _FakeMap:
    def __init__(self) -> None:
        self.fakes: dict[str, str] = {}
        self._pattern: Optional[re.Pattern] = None
        self._sorted: Optional[list[str]] = None
        self._firsts: frozenset[str] = frozenset()
        self._longest = 0

    def changed(self) -> None:
        self._pattern = None
        self._sorted = None

    def pattern(self) -> re.Pattern:
        if self._pattern is None:
            keys = sorted(self.fakes, key=len, reverse=True)
            self._pattern = re.compile("|".join(re.escape(k) for k in keys)) if keys else _NEVER
        return self._pattern

    def held_suffix_len(self, text: str) -> int:
        """Length of the longest tail of text that is a proper prefix of a fake."""
        if self._sorted is None:
            self._sorted = sorted(self.fakes)
            self._firsts = frozenset(k[0] for k in self._sorted)
            self._longest = max(map(len, self._sorted), default=0)
        keys = self._sorted
        for i in range(max(0, len(text) - self._longest + 1), len(text)):
            if text[i] not in self._firsts:
                continue
            tail = text[i:]
            j = bisect.bisect_right(keys, tail)
            if j < len(keys) and keys[j].startswith(tail):
                return len(text) - i
        return 0

    def search(self, text: str) -> bool:
        return self.pattern().search(text) is not None

    def sub(self, text: str) -> str:
        return self.pattern().sub(lambda m: self.fakes[m.group(0)], text)


class _KnownFakes(_FakeMap):
    """Fakes one API key was sent recently, so a later turn that echoes one still gets the real value."""

    # Fakes keep their secret's shape, so the fixed secret regex finds them and no per-change recompile is needed.
    def search(self, text: str) -> bool:
        return bool(self.fakes) and any(m.group(0) in self.fakes for m in _SECRET_RE.finditer(text))

    def sub(self, text: str) -> str:
        if not self.fakes:
            return text
        return _SECRET_RE.sub(lambda m: self.fakes.get(m.group(0), m.group(0)), text)


class _CallState(_FakeMap):
    def __init__(self, known: Optional[_KnownFakes] = None, scope: Any = None) -> None:
        super().__init__()
        self.created = time.monotonic()
        self.holders: set[int] = set()
        self.known = known
        self.scope = scope
        self.remote: Any = None

    def merge(self, other: "_CallState") -> None:
        self.fakes.update(other.fakes)
        self.holders |= other.holders
        self.known = self.known or other.known
        self.remote = self.remote or other.remote
        self.changed()
        self.created = time.monotonic()

    def _maps(self) -> tuple[_FakeMap, ...]:
        return (self,) if self.known is None else (self, self.known)

    def contains(self, text: str) -> bool:
        return any(_FakeMap.search(self, text) if m is self else m.search(text) for m in self._maps())

    def restore(self, text: str) -> str:
        if not text:
            return text
        for fake_map in self._maps():
            text = _FakeMap.sub(self, text) if fake_map is self else fake_map.sub(text)
        return text

    def held_suffix_len(self, text: str) -> int:
        return max(_FakeMap.held_suffix_len(m, text) for m in self._maps())


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
    def __init__(
        self,
        key: bytes,
        ttl_seconds: float = 3600.0,
        max_calls: int = 10000,
        clean_cache_size: int = 4096,
        clean_cache_min_len: int = 4096,
        max_known_fakes: int = 2000,
        shared: Optional[SharedFakes] = None,
    ) -> None:
        self._key = key
        self._shared = shared
        self._ttl = ttl_seconds
        self._max_calls = max_calls
        self._calls: OrderedDict[str, _CallState] = OrderedDict()
        self._clean: OrderedDict[bytes, None] = OrderedDict()
        self._clean_size = clean_cache_size
        self._clean_min_len = clean_cache_min_len
        self._max_known = max_known_fakes
        self._known: dict[Any, _KnownFakes] = {}
        self._known_seen: OrderedDict[tuple, float] = OrderedDict()

    def pending_calls(self) -> int:
        return len(self._calls)

    def mask_token_count(self, kwargs: dict) -> dict:
        state = _CallState()
        return {
            k: _map_strings(v, lambda text: self._mask_text(text, state)) if k in _TOKEN_COUNT_FIELDS else v
            for k, v in kwargs.items()
        }

    def wants_stream(self, request_data: dict) -> bool:
        try:
            return self._calls.get(request_data.get("litellm_call_id")) is not None
        except Exception:  # noqa: BLE001 - a stream decision must never raise
            return False

    # async_* names mirror LiteLLM's CustomLogger hooks; callers await them.
    async def async_pre_call_hook(self, user_api_key_dict, _cache, data: dict, call_type: str):  # NOSONAR
        self._prune()
        call_id = data.get("litellm_call_id")
        fields = _MASKED_FIELDS.get(call_type)
        if not fields or not call_id:
            return data

        scope = _scope(user_api_key_dict)
        state = _CallState(self._known.get(scope), scope)
        masked = {}
        for field in fields:
            if field in data:
                mask = _FIELD_MAPPERS.get(field, _map_strings)
                value = mask(data[field], lambda text: self._mask_text(text, state))
                if value is not data[field]:
                    masked[field] = value
        if state.fakes:
            data.update(masked)
            self._remember(scope, state.fakes)
            state.known = self._known.get(scope)
            if self._shared is not None:
                self._shared.put(scope, state.fakes)
        if call_type in _NO_REPLY_HOOKS:
            return data
        if self._shared is not None:
            # Read now, while the provider works, so the reply hook rarely waits on Valkey.
            state.remote = self._shared.fetch(scope)
        if state.known is None and state.remote is None:
            return data

        state.holders.add(_holder(data))
        # Clients can set the call id (x-litellm-call-id), so in-flight calls may share one.
        existing = self._calls.get(call_id)
        if existing is None:
            self._calls[call_id] = state
        else:
            existing.merge(state)
            self._calls.move_to_end(call_id)
        while len(self._calls) > self._max_calls:
            self._calls.popitem(last=False)
        return data

    async def async_post_call_success_hook(self, data: dict, response, **_):  # NOSONAR
        call_id = (data or {}).get("litellm_call_id")
        state = self._calls.get(call_id)
        if state is None:
            return None
        self._release(call_id, data)
        await self._load_remote(state)
        if isinstance(response, dict) and "candidates" not in response:
            return _map_strings(response, state.restore)
        return _restore_slots(response, state, _response_texts)

    async def async_post_call_failure_hook(self, request_data: dict, **_) -> None:  # NOSONAR
        self._release((request_data or {}).get("litellm_call_id"), request_data)

    async def async_post_call_streaming_iterator_hook(self, response, request_data: dict, **_):
        call_id = (request_data or {}).get("litellm_call_id")
        state = self._calls.get(call_id)
        stream = response
        try:
            if state is not None:
                await self._load_remote(state)
                if state.fakes or state.known is not None:
                    stream = _restore_stream(response, _StreamRestorer(state))
            async for chunk in stream:
                yield chunk
        finally:
            if state is not None:
                self._release(call_id, request_data)

    async def _load_remote(self, state: _CallState) -> None:
        task, state.remote = state.remote, None
        if task is None:
            return
        fakes = await self._shared.result(task)
        if fakes:
            self._remember(state.scope, fakes)
            state.known = self._known.get(state.scope)

    def _release(self, call_id: Any, data: Any) -> None:
        # Idempotent per request: LiteLLM can run both the stream and failure hooks for one call.
        state = self._calls.get(call_id)
        if state is None:
            return
        state.holders.discard(_holder(data))
        if not state.holders:
            del self._calls[call_id]

    def _prune(self) -> None:
        cutoff = time.monotonic() - self._ttl
        while self._calls:
            oldest = next(iter(self._calls.values()))
            if oldest.created >= cutoff:
                break
            self._calls.popitem(last=False)
        while self._known_seen and next(iter(self._known_seen.values())) < cutoff:
            self._forget(*self._known_seen.popitem(last=False)[0])

    def _remember(self, scope: Any, fakes: dict[str, str]) -> None:
        known = self._known.setdefault(scope, _KnownFakes())
        now = time.monotonic()
        for fake, real in fakes.items():
            entry = (scope, fake)
            if entry not in self._known_seen:
                known.fakes[fake] = real
                known.changed()
            self._known_seen[entry] = now
            self._known_seen.move_to_end(entry)
        while len(self._known_seen) > self._max_known:
            self._forget(*self._known_seen.popitem(last=False)[0])

    def _forget(self, scope: Any, fake: str) -> None:
        known = self._known.get(scope)
        if known is None:
            return
        known.fakes.pop(fake, None)
        known.changed()
        if not known.fakes:
            del self._known[scope]

    def _mask_text(self, text: str, state: _CallState) -> str:
        if len(text) < self._clean_min_len:
            return self._scan(text, state)
        digest = hashlib.blake2b(text.encode("utf-8", "surrogatepass"), digest_size=16).digest()
        if digest in self._clean:
            self._clean.move_to_end(digest)
            return text
        out = self._scan(text, state)
        if out is text:
            self._clean[digest] = None
            if len(self._clean) > self._clean_size:
                self._clean.popitem(last=False)
        return out

    def _scan(self, text: str, state: _CallState) -> str:
        def replace(match: re.Match) -> str:
            i = int(match.lastgroup[1:])
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


def _scope(user_api_key_dict: Any) -> Any:
    # Per virtual key, so a reply on one key can never restore a secret another key sent.
    scope = getattr(user_api_key_dict, "api_key", None)
    return scope if isinstance(scope, str) else None


def _holder(data: Any) -> int:
    data = data or {}
    # Not litellm_logging_obj: post_call_failure_hook pops it before callbacks run.
    return id(data.get("proxy_server_request") or data)


async def _restore_stream(response, restorer: _StreamRestorer):
    async for chunk in response:
        try:
            out = restorer.process(chunk)
        except Exception as exc:  # noqa: BLE001 - a restore bug must not kill the stream
            _log_warning("secret masking stream restore failed open: %s", type(exc).__name__)
            for item in restorer.fail_open(chunk):
                yield item
            break
        for item in out:
            yield item
    else:
        try:
            out = restorer.finish()
        except Exception as exc:  # noqa: BLE001 - a restore bug must not kill the stream
            _log_warning("secret masking stream finish failed open: %s", type(exc).__name__)
            out = restorer.fail_open(None)
        for item in out:
            yield item
        return
    async for rest in response:
        yield rest


def _map_strings(value: Any, fn: Callable[[str], str]) -> Any:
    """Applies fn to every string outside opaque blocks, sharing unchanged subtrees with the input."""
    if isinstance(value, str):
        return value if _DATA_URL_RE.match(value) else fn(value)
    if isinstance(value, list):
        out = [_map_strings(item, fn) for item in value]
        return out if any(a is not b for a, b in zip(out, value)) else value
    if isinstance(value, dict):
        kind = _kind(value)
        if kind in _OPAQUE_BLOCK_TYPES:
            return value
        kept = _OPAQUE_FIELDS.get(kind, ())
        return _map_dict(value, lambda k, v: v if k in kept else _map_strings(v, fn))
    return value


def _map_dict(value: dict, fn: Callable[[Any, Any], Any]) -> dict:
    out = {k: fn(k, v) for k, v in value.items()}
    return out if any(out[k] is not value[k] for k in value) else value


def _map_gemini_content(value: Any, fn: Callable[[str], str]) -> Any:
    if isinstance(value, list):
        out = [_map_gemini_content(item, fn) for item in value]
        return out if any(a is not b for a, b in zip(out, value)) else value
    if isinstance(value, dict) and isinstance(value.get("parts"), list):
        return _map_dict(value, lambda k, v: _map_gemini_parts(v, fn) if k == "parts" else v)
    return _map_strings(value, fn)


def _map_gemini_parts(parts: list, fn: Callable[[str], str]) -> list:
    out = [_map_gemini_part(part, fn) for part in parts]
    return out if any(a is not b for a, b in zip(out, parts)) else parts


def _map_gemini_part(part: Any, fn: Callable[[str], str]) -> Any:
    if not isinstance(part, dict):
        return _map_strings(part, fn)
    if part.get("thought") is True:
        return part
    return _map_dict(part, lambda k, v: v if k in _GEMINI_OPAQUE_PART_KEYS else _map_strings(v, fn))


def _map_gemini_config(config: Any, fn: Callable[[str], str]) -> Any:
    if not isinstance(config, dict):
        return config
    return _map_dict(config, lambda k, v: _map_gemini_content(v, fn) if k in _GEMINI_SYSTEM_KEYS else v)


def _mask_json_frame(frame: Any, fn: Callable[[str], str]) -> Any:
    if not isinstance(frame, str):
        return frame
    try:
        event = json.loads(frame)
    except ValueError:
        return frame
    if not isinstance(event, dict):
        return frame
    out = {k: _map_strings(v, fn) if k in ("instructions", "input", "response") else v for k, v in event.items()}
    return json.dumps(out) if any(out[k] is not event[k] for k in event) else frame


_FIELD_MAPPERS = {
    "contents": _map_gemini_content,
    "systemInstruction": _map_gemini_content,
    "system_instruction": _map_gemini_content,
    "config": _map_gemini_config,
    "first_message": _mask_json_frame,
}


def _restore_slots(obj: Any, state: _CallState, walk: Callable[[Any], Any]) -> Any:
    """Returns a restored deep copy of obj, or None when no slot yielded by walk holds a fake."""
    if not any(state.contains(text) for _, _, text in walk(obj)):
        return None
    restored = copy.deepcopy(obj)
    for owner, key, text in walk(restored):
        _set(owner, key, state.restore(text))
    return restored


def _response_texts(response: Any):
    """Yields (owner, key, text) for every model-written string in a chat, text or Responses API reply."""
    for choice in _get(response, "choices") or ():
        yield from _slots(choice, "text")
        message = _get(choice, "message")
        yield from _slots(message, "content")
        for call in _get(message, "tool_calls") or ():
            yield from _slots(_get(call, "function"), "arguments")
    for item in _get(response, "output") or ():
        yield from _item_texts(item)
    for candidate in _get(response, "candidates") or ():
        for part in _get(_get(candidate, "content"), "parts") or ():
            yield from _gemini_part_texts(part)


def _gemini_part_texts(part: Any):
    if _get(part, "thought") is True:
        return
    yield from _slots(part, "text")
    call = _get(part, "functionCall") or _get(part, "function_call")
    args = _get(call, "args")
    if isinstance(args, dict):
        yield from _json_slots(args)


def _gemini_append_tail(candidate: dict, last_text: Optional[dict], tail: str) -> None:
    if last_text is not None:
        last_text["text"] += tail
        return
    if not isinstance(candidate.get("content"), dict):
        candidate["content"] = {"role": "model"}
    if not isinstance(candidate["content"].get("parts"), list):
        candidate["content"]["parts"] = []
    candidate["content"]["parts"].insert(0, {"text": tail})


def _json_slots(value: Any):
    items = value.items() if isinstance(value, dict) else enumerate(value)
    for key, child in items:
        if isinstance(child, str):
            yield value, key, child
        elif isinstance(child, (dict, list)):
            yield from _json_slots(child)


def _item_texts(item: Any):
    kind = _kind(item)
    if kind == "message":
        for part in _get(item, "content") or ():
            yield from _part_texts(part)
    elif kind == "function_call":
        yield from _slots(item, "arguments")
    elif kind == "custom_tool_call":
        yield from _slots(item, "input")


def _part_texts(part: Any):
    if _kind(part) in _RESPONSES_TEXT_PARTS:
        yield from _slots(part, "text", "refusal")


def _event_texts(event: Any):
    done = _RESPONSES_DONE.get(_kind(event))
    if done is not None:
        yield from _slots(event, done[1])
    response = _get(event, "response")
    if response is not None:
        yield from _response_texts(response)
    item = _get(event, "item")
    if item is not None:
        yield from _item_texts(item)
    part = _get(event, "part")
    if part is not None:
        yield from _part_texts(part)


def _slots(owner: Any, *keys: str):
    for key in keys:
        value = _get(owner, key)
        if isinstance(value, str):
            yield owner, key, value


def _get(owner: Any, key: str) -> Any:
    if owner is None:
        return None
    if isinstance(owner, dict):
        return owner.get(key)
    return getattr(owner, key, None)


def _kind(owner: Any) -> str:
    # JSON schemas in tool input use "type": [..] or {..}; those are unhashable.
    kind = _get(owner, "type")
    return kind if isinstance(kind, str) else ""


def _set(owner: Any, key: Any, value: str) -> None:
    if isinstance(owner, (dict, list)):
        owner[key] = value
    else:
        setattr(owner, key, value)


class _StreamRestorer:
    def __init__(self, state: _CallState) -> None:
        self.hold = _Holdback(state)
        self.delta_types: dict[int, str] = {}
        self.sse_buffer = ""
        self.mode: Optional[str] = None
        self.decoder = codecs.getincrementaldecoder("utf-8")()
        self.last_chat_chunk: Any = None
        self.chat_choices: dict[int, Any] = {}
        self.delta_cls: Any = None
        self.tool_templates: dict[tuple, Any] = {}
        self.responses_templates: dict[tuple, Any] = {}
        self._checkpoint: tuple = ("", b"", {})

    def process(self, chunk: Any) -> list:
        out = self._process(chunk)
        self._checkpoint = (self.sse_buffer, self.decoder.getstate()[0], dict(self.hold.held))
        return out

    def _process(self, chunk: Any) -> list:
        if isinstance(chunk, (bytes, bytearray)):
            self.mode = "bytes"
            return self._sse(self.decoder.decode(bytes(chunk)))
        if isinstance(chunk, str):
            self.mode = "str"
            return self._sse(chunk)
        if isinstance(chunk, dict):
            self.mode = "dict"
            return self._events(chunk)
        if _is_responses_event(chunk):
            self.mode = "responses"
            return self._responses_event(chunk)
        choices = getattr(chunk, "choices", None)
        if choices is not None:
            if not choices:
                return [*self._chat_tail(), chunk]
            return [self._chat(chunk)]
        return [chunk]

    def finish(self) -> list:
        if self.mode in ("bytes", "str"):
            return self._sse_tail(b"" if self.mode == "bytes" else "")
        return self._flush_tail()

    def _flush_tail(self) -> list:
        if self.mode == "dict":
            return self._flush_all_events()
        if self.mode == "responses":
            return self._flush_responses()
        return self._chat_tail()

    def fail_open(self, chunk: Any) -> list:
        """Rewinds to the last good chunk and passes everything not yet sent through raw."""
        sse_buffer, undecoded, held = self._checkpoint
        self.sse_buffer = sse_buffer
        self.decoder.reset()
        self.hold.held = held
        if self.mode in ("bytes", "str"):
            raw = undecoded + bytes(chunk or b"") if self.mode == "bytes" else (chunk or "")
            return self._sse_tail(raw)
        try:
            flushed = self._flush_tail()
        except Exception:  # noqa: BLE001 - held text is lost rather than the whole stream
            flushed = []
        return flushed if chunk is None else [*flushed, chunk]

    def _sse_tail(self, raw: Any) -> list:
        if self.mode == "bytes" and not raw:
            raw = self.decoder.getstate()[0]
        # sse_buffer starts on an event boundary, so flushed events go before it.
        text = self._format(self._flush_all_events()) + self.sse_buffer
        self.sse_buffer = ""
        out = text.encode() + raw if self.mode == "bytes" else text + raw
        return [out] if out else []

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
            (f"event: {e['type']}\n" if isinstance(e.get("type"), str) else "") + f"data: {json.dumps(e)}\n\n"
            for e in events
        )

    def _events(self, event: dict) -> list:
        if _is_responses_event(event):
            return self._responses_event(event)
        if isinstance(event.get("candidates"), list):
            return self._gemini_event(event)
        kind = _kind(event)
        index = event.get("index")
        if kind == "content_block_delta" and isinstance(index, int):
            delta = event.get("delta") or {}
            field = _STREAM_DELTA_FIELDS.get(_kind(delta))
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
        gemini = [k[1] for k in self.hold.held if isinstance(k, tuple) and k[0] == "gemini"]
        return [
            *(self._flush_event(i) for i in indices),
            *self._flush_responses(),
            *({"candidates": [{"index": c, "content": {"role": "model", "parts": [{"text": self.hold.flush(("gemini", c))}]}}]}
              for c in gemini),
        ]

    def _gemini_event(self, event: dict) -> list:
        restored = copy.deepcopy(event)
        changed = False
        for n, candidate in enumerate(restored["candidates"]):
            if isinstance(candidate, dict):
                changed |= self._gemini_candidate(candidate, ("gemini", candidate.get("index", n)))
        return [restored] if changed else [event]

    def _gemini_candidate(self, candidate: dict, key: tuple) -> bool:
        parts = [p for p in _get(candidate.get("content"), "parts") or () if isinstance(p, dict)]
        changed = False
        last_text = None
        for part in parts:
            if part.get("thought") is True:
                continue
            if isinstance(part.get("text"), str):
                changed |= self._gemini_feed_text(key, part)
                last_text = part
            changed |= self._gemini_restore_part(part)
        if candidate.get("finishReason") and key in self.hold.held:
            _gemini_append_tail(candidate, last_text, self.hold.flush(key))
            changed = True
        return changed

    def _gemini_feed_text(self, key: tuple, part: dict) -> bool:
        text = self.hold.feed(key, part["text"])
        changed = text != part["text"]
        part["text"] = text
        return changed

    def _gemini_restore_part(self, part: dict) -> bool:
        changed = False
        for owner, slot, value in _gemini_part_texts({k: v for k, v in part.items() if k != "text"}):
            real = self.hold.state.restore(value)
            if real != value:
                _set(owner, slot, real)
                changed = True
        return changed

    def _responses_event(self, event: Any) -> list:
        kind = _kind(event)
        if kind in _RESPONSES_DELTAS:
            delta = _get(event, "delta")
            if not isinstance(delta, str):
                return [event]
            key = _responses_key(event, kind)
            self.responses_templates[key] = event
            text = self.hold.feed(key, delta)
            return [event] if text == delta else [_with(event, delta=text)]
        flushed = []
        if kind in _RESPONSES_DONE:
            key = _responses_key(event, _RESPONSES_DONE[kind][0])
            if key in self.hold.held:
                flushed.append(self._flush_responses_key(key))
        elif kind in _RESPONSES_TERMINAL:
            flushed = self._flush_responses()
        restored = _restore_slots(event, self.hold.state, _event_texts)
        return [*flushed, event if restored is None else restored]

    def _flush_responses(self) -> list:
        keys = [k for k in self.hold.held if isinstance(k, tuple) and k[0] == "responses"]
        return [self._flush_responses_key(k) for k in keys]

    def _flush_responses_key(self, key: tuple) -> Any:
        return _with(self.responses_templates[key], delta=self.hold.flush(key))

    def _flush_event(self, index: int) -> dict:
        delta_type = self.delta_types.get(index, "text_delta")
        return {
            "type": "content_block_delta",
            "index": index,
            "delta": {"type": delta_type, _STREAM_DELTA_FIELDS[delta_type]: self.hold.flush(index)},
        }

    def _chat(self, chunk: Any) -> Any:
        out = chunk
        for n, choice in enumerate(chunk.choices):
            self.last_chat_chunk = chunk
            self.chat_choices[choice.index] = choice
            delta = getattr(choice, "delta", None)
            if delta is not None:
                self.delta_cls = self.delta_cls or type(delta)
                out = self._chat_choice(chunk, out, n, choice, delta)
            else:
                out = self._text_choice(chunk, out, n, choice)
        return out

    def _text_choice(self, chunk: Any, out: Any, n: int, choice: Any) -> Any:
        content = getattr(choice, "text", None)
        if isinstance(content, str):
            text = self.hold.feed(("text", choice.index), content)
            if text != content:
                out = _own(chunk, out)
                out.choices[n].text = text
        if getattr(choice, "finish_reason", None) and self._holds_for(choice.index):
            out = _own(chunk, out)
            self._chat_flush_choice(out.choices[n])
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

    def _chat_tail(self) -> list:
        if self.last_chat_chunk is None or not self.hold.held:
            return []
        chunk = copy.deepcopy(self.last_chat_chunk)
        if getattr(chunk, "usage", None) is not None:
            chunk.usage = None
        held = sorted({k[1] for k in self.hold.held if isinstance(k, tuple)})
        chunk.choices = [copy.deepcopy(self.chat_choices[i]) for i in held]
        for choice in chunk.choices:
            choice.finish_reason = None
            if getattr(choice, "delta", None) is None:
                choice.text = None
            else:
                choice.delta = self.delta_cls()
            self._chat_flush_choice(choice)
        return [chunk]

    def _chat_flush_choice(self, choice: Any) -> None:
        if getattr(choice, "delta", None) is None:
            tail = self.hold.flush(("text", choice.index))
            if tail:
                choice.text = (getattr(choice, "text", None) or "") + tail
            return
        tail = self.hold.flush(("content", choice.index))
        if tail:
            choice.delta.content = (getattr(choice.delta, "content", None) or "") + tail
        calls = list(getattr(choice.delta, "tool_calls", None) or ())
        by_index = {getattr(c, "index", None): c for c in calls}
        for key in [k for k in self.hold.held if isinstance(k, tuple) and k[0] == "tool" and k[1] == choice.index]:
            tail = self.hold.flush(key)
            if key[2] in by_index:
                by_index[key[2]].function.arguments += tail
                continue
            call = copy.deepcopy(self.tool_templates[key])
            call.id = None
            call.function.name = None
            call.function.arguments = tail
            calls.append(call)
        if calls:
            choice.delta.tool_calls = calls


def _is_responses_event(event: Any) -> bool:
    return _kind(event).startswith("response.")


def _responses_key(event: Any, delta_kind: str) -> tuple:
    return ("responses", delta_kind, _get(event, "item_id"), _get(event, "output_index"), _get(event, "content_index"))


def _with(event: Any, **fields: Any) -> Any:
    if isinstance(event, dict):
        return {**event, **fields}
    out = copy.copy(event)
    for key, value in fields.items():
        setattr(out, key, value)
    return out


def _own(chunk: Any, out: Any) -> Any:
    return copy.deepcopy(chunk) if out is chunk else out


def _parse_sse_data(block: str) -> Optional[dict]:
    lines = [line[5:] for line in block.split("\n") if line.startswith("data:")]
    if not lines:
        return None
    try:
        event = json.loads("\n".join(line[1:] if line.startswith(" ") else line for line in lines))
    except ValueError:
        return None
    return event if isinstance(event, dict) else None


def _key_from_env() -> bytes:
    salt = os.environ.get("LITELLM_SALT_KEY")
    if not salt:
        _log_warning("LITELLM_SALT_KEY is not set; secret masking fakes will differ per replica")
        return os.urandom(32)
    return hmac.new(salt.encode(), b"litellm-secret-masking", hashlib.sha256).digest()


def install_token_count_masking(middleware: SecretMaskingMiddleware, proxy_server: Any) -> None:
    """Masks the body /v1/messages/count_tokens and friends send to the provider; they skip every proxy hook."""
    original = getattr(proxy_server, "_try_provider_token_count", None)
    if original is None:
        _log_warning("secret masking: LiteLLM has no _try_provider_token_count; provider token count calls go unmasked")
        return
    if getattr(original, "_secret_masking", False):
        return

    async def masked(*args, **kwargs):
        try:
            if args:
                raise TypeError("positional arguments cannot be masked")
            kwargs = middleware.mask_token_count(kwargs)
        except Exception as exc:  # noqa: BLE001 - None makes LiteLLM count locally instead
            _log_warning("secret masking token count failed closed: %s", type(exc).__name__)
            return None
        return await original(**kwargs)

    masked._secret_masking = True
    proxy_server._try_provider_token_count = masked


secret_masking = SecretMaskingMiddleware(key=_key_from_env(), shared=shared_from_env())
# Callbacks load from inside proxy_server's startup, so the module is already imported.
install_token_count_masking(secret_masking, sys.modules.get("litellm.proxy.proxy_server"))
