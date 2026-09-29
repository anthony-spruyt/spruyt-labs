import copy
import importlib
import json
import os
import sys
import time
import types
from types import SimpleNamespace

import pytest


_HERE = os.path.dirname(__file__)
_PLUGIN_DIR = os.path.dirname(_HERE)
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)


# Built by concatenation so secret scanners don't flag the fixtures.
GH_PAT = "gh" + "p_" + "aB3dE5gH7jK9mN1pQ3sT5vW7yZ9bC1dE3fG5"
GH_PAT_2 = "gh" + "p_" + "Zy8xW6vU4tS2rQ0pO8nM6lK4jI2hG0fE8dC6"
OAUTH = "sk-" + "ant-oat01-" + "Qw3rTy7uIo9pAs1dFg5hJk7lZx9cVb3nM1qW5eR7tY9uI1oP3aS5dF7gH9jK1lZ3"
GOOGLE = "AI" + "za" + "SyA1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q"
SL_KEY = "sl" + "_" + "Xk9fQ2mW7pL4rT8vN3bH6jD1sZ5cY0gA2eU7iO4wRt6yU8iP0aS2dF4gH6jK8lZ1"
PEM_BEGIN = "-----BEGIN " + "PRIVATE KEY-----"
PEM_END = "-----END " + "PRIVATE KEY-----"
PEM = PEM_BEGIN + "\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7\n" + PEM_END


@pytest.fixture(autouse=True)
def fake_litellm(monkeypatch):
    litellm = types.ModuleType("litellm")
    logging = types.ModuleType("litellm._logging")

    class Logger:
        def __init__(self):
            self.warnings = []

        def warning(self, *args, **kwargs):
            self.warnings.append((args, kwargs))

    logging.verbose_proxy_logger = Logger()
    monkeypatch.setitem(sys.modules, "litellm", litellm)
    monkeypatch.setitem(sys.modules, "litellm._logging", logging)
    return logging


@pytest.fixture
def mod():
    sys.modules.pop("secret_masking", None)
    return importlib.import_module("secret_masking")


@pytest.fixture
def mw(mod):
    return mod.SecretMaskingMiddleware(key=b"test-key")


def _request(text, call_id="call-1"):
    return {
        "litellm_call_id": call_id,
        "system": "You are helpful.",
        "messages": [{"role": "user", "content": [{"type": "text", "text": text}]}],
    }


def _user_text(data):
    return data["messages"][0]["content"][0]["text"]


async def _mask(mw, text, call_id="call-1"):
    return await mw.async_pre_call_hook(None, None, _request(text, call_id), "anthropic_messages")


def _classes(s):
    return [
        "d" if c.isdigit() else "l" if c.islower() else "u" if c.isupper() else c
        for c in s
    ]



async def test_masks_github_pat_with_same_shape_fake(mw):
    out = await _mask(mw, f"token is {GH_PAT} ok")

    masked = _user_text(out)
    fake = masked.split()[2]
    assert GH_PAT not in masked
    assert fake.startswith("ghp_")
    assert len(fake) == len(GH_PAT)
    assert _classes(fake) == _classes(GH_PAT)
    assert masked == f"token is {fake} ok"


async def test_same_secret_gets_same_fake_across_requests(mw):
    first = _user_text(await _mask(mw, GH_PAT, "call-1"))
    second = _user_text(await _mask(mw, GH_PAT, "call-2"))

    assert first == second


async def test_different_secrets_get_different_fakes(mw):
    out = _user_text(await _mask(mw, f"{GH_PAT} {GH_PAT_2}"))

    a, b = out.split()
    assert a != b


async def test_fakes_depend_on_the_key(mod):
    a = mod.SecretMaskingMiddleware(key=b"one")
    b = mod.SecretMaskingMiddleware(key=b"two")

    assert _user_text(await _mask(a, GH_PAT)) != _user_text(await _mask(b, GH_PAT))


async def test_keeps_multi_part_prefix(mw):
    fake = _user_text(await _mask(mw, OAUTH))

    assert fake.startswith("sk-ant-oat01-")
    assert fake != OAUTH
    assert len(fake) == len(OAUTH)


async def test_masks_google_key(mw):
    fake = _user_text(await _mask(mw, GOOGLE))

    assert fake.startswith("AIza")
    assert fake != GOOGLE


async def test_masks_pem_body_and_keeps_armour(mw):
    fake = _user_text(await _mask(mw, PEM))

    assert fake != PEM
    assert fake.startswith(PEM_BEGIN + "\n")
    assert fake.endswith("\n" + PEM_END)
    assert _classes(fake) == _classes(PEM)


async def test_many_unterminated_pem_headers_mask_quickly(mw):
    line = PEM_BEGIN
    text = "\n".join(f"file{i}.pem:1:{line}" for i in range(5000))

    start = time.monotonic()
    out = await _mask(mw, text)

    assert time.monotonic() - start < 1.0
    assert _user_text(out) == text


async def test_masks_pem_after_unterminated_header(mw):
    fake = _user_text(await _mask(mw, PEM_BEGIN + "\n" + PEM))

    assert "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7" not in fake


async def test_masks_spruyt_labs_key(mw):
    fake = _user_text(await _mask(mw, f"DB_PASSWORD={SL_KEY}")).split("=")[1]

    assert fake != SL_KEY
    assert fake.startswith("sl_")
    assert _classes(fake) == _classes(SL_KEY)


async def test_masks_long_spruyt_labs_key(mw):
    key = SL_KEY + "Qw3eR5tY7uI9oP1a"
    fake = _user_text(await _mask(mw, key))

    assert fake != key
    assert len(fake) == len(key)


async def test_masks_32_char_spruyt_labs_key(mw):
    key = SL_KEY[:32]
    fake = _user_text(await _mask(mw, key))

    assert fake != key
    assert fake.startswith("sl_")
    assert len(fake) == 32


async def test_ignores_sl_key_shorter_than_minimum(mw):
    text = SL_KEY[:26]

    assert _user_text(await _mask(mw, text)) == text


async def test_ignores_sl_identifiers_that_are_not_keys(mw):
    text = "call sl_parse_config() or sl_Xk9fQ2 or my_sl_Xk9fQ2mW7pL4rT8vN3bH6jD1sZ5cY0gA2eU7iO4w"

    assert _user_text(await _mask(mw, text)) == text


async def test_ignores_lowercase_words_with_key_prefix(mw):
    text = "pip install sk-learn-extensions-for-everyone"

    assert _user_text(await _mask(mw, text)) == text


async def test_no_secrets_returns_request_untouched(mw):
    data = _request("nothing to see here")
    snapshot = copy.deepcopy(data)

    out = await mw.async_pre_call_hook(None, None, data, "anthropic_messages")

    assert out is data
    assert out == snapshot
    assert mw.pending_calls() == 0


async def test_skips_request_without_call_id(mw):
    data = _request(GH_PAT)
    del data["litellm_call_id"]

    out = await mw.async_pre_call_hook(None, None, data, "anthropic_messages")

    assert _user_text(out) == GH_PAT


async def test_masks_system_prompt_and_nested_tool_results(mw):
    data = {
        "litellm_call_id": "call-1",
        "system": [{"type": "text", "text": f"env: {GH_PAT}"}],
        "messages": [{
            "role": "user",
            "content": [{
                "type": "tool_result",
                "tool_use_id": "t1",
                "content": [{"type": "text", "text": f"GOOGLE_KEY={GOOGLE}"}],
            }],
        }],
    }

    out = await mw.async_pre_call_hook(None, None, data, "anthropic_messages")

    dumped = json.dumps(out)
    assert GH_PAT not in dumped
    assert GOOGLE not in dumped


async def test_masks_chat_completions_messages(mw):
    data = {
        "litellm_call_id": "call-1",
        "messages": [
            {"role": "user", "content": f"key {GH_PAT}"},
            {"role": "assistant", "tool_calls": [{
                "id": "c1", "type": "function",
                "function": {"name": "sh", "arguments": json.dumps({"cmd": PEM})},
            }]},
        ],
    }

    out = await mw.async_pre_call_hook(None, None, data, "acompletion")

    dumped = json.dumps(out)
    assert GH_PAT not in dumped
    assert "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7" not in dumped


async def test_does_not_touch_thinking_or_base64_blocks(mw):
    thinking = {"type": "thinking", "thinking": f"saw {GH_PAT}", "signature": "sig"}
    image = {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": GH_PAT}}
    data = {
        "litellm_call_id": "call-1",
        "messages": [
            {"role": "assistant", "content": [thinking]},
            {"role": "user", "content": [image, {"type": "text", "text": GH_PAT}]},
        ],
    }

    out = await mw.async_pre_call_hook(None, None, data, "anthropic_messages")

    assert out["messages"][0]["content"][0] == thinking
    assert out["messages"][1]["content"][0] == image
    assert out["messages"][1]["content"][1]["text"] != GH_PAT


async def test_original_request_objects_are_not_mutated(mw):
    data = _request(GH_PAT)
    messages = data["messages"]
    snapshot = copy.deepcopy(messages)

    await mw.async_pre_call_hook(None, None, data, "anthropic_messages")

    assert messages == snapshot



async def test_restores_anthropic_response_text_and_tool_input(mw):
    data = await _mask(mw, f"use {GH_PAT}")
    fake = _user_text(data).split()[1]
    response = {
        "type": "message",
        "content": [
            {"type": "thinking", "thinking": f"I have {fake}", "signature": "sig"},
            {"type": "text", "text": f"Using {fake}"},
            {"type": "tool_use", "id": "t1", "name": "sh", "input": {"cmd": f"gh auth login {fake}"}},
        ],
    }
    original = copy.deepcopy(response)

    out = await mw.async_post_call_success_hook(data=data, user_api_key_dict=None, response=response)

    assert out["content"][0]["thinking"] == f"I have {fake}"
    assert out["content"][1]["text"] == f"Using {GH_PAT}"
    assert out["content"][2]["input"]["cmd"] == f"gh auth login {GH_PAT}"
    assert response == original
    assert mw.pending_calls() == 0


async def test_restores_chat_response_object(mw):
    data = await _mask(mw, f"use {GH_PAT}")
    fake = _user_text(data).split()[1]
    message = SimpleNamespace(
        content=f"ok {fake}",
        tool_calls=[SimpleNamespace(function=SimpleNamespace(
            name="sh", arguments=json.dumps({"cmd": fake})))],
    )
    response = SimpleNamespace(choices=[SimpleNamespace(message=message)])

    out = await mw.async_post_call_success_hook(data=data, user_api_key_dict=None, response=response)

    assert out.choices[0].message.content == f"ok {GH_PAT}"
    assert json.loads(out.choices[0].message.tool_calls[0].function.arguments) == {"cmd": GH_PAT}
    assert response.choices[0].message.content == f"ok {fake}"


async def test_restores_json_escaped_multiline_fake(mw):
    data = await _mask(mw, PEM)
    fake = _user_text(data)
    response = {"content": [{"type": "tool_use", "input": {"raw": json.dumps({"k": fake})}}]}

    out = await mw.async_post_call_success_hook(data=data, user_api_key_dict=None, response=response)

    assert json.loads(out["content"][0]["input"]["raw"]) == {"k": PEM}


async def test_response_without_mapping_is_returned_as_is(mw):
    response = {"content": [{"type": "text", "text": "hi"}]}

    out = await mw.async_post_call_success_hook(
        data={"litellm_call_id": "unknown"}, user_api_key_dict=None, response=response)

    assert out is None or out is response



def _sse(event):
    return f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"


def _text_stream_events(pieces, index=0):
    events = [{"type": "message_start", "message": {"id": "m1"}},
              {"type": "content_block_start", "index": index,
               "content_block": {"type": "text", "text": ""}}]
    events += [{"type": "content_block_delta", "index": index,
                "delta": {"type": "text_delta", "text": p}} for p in pieces]
    events += [{"type": "content_block_stop", "index": index},
               {"type": "message_stop"}]
    return events


async def _agen(items):
    for item in items:
        yield item


async def _collect(mw, chunks, data):
    return [c async for c in mw.async_post_call_streaming_iterator_hook(
        user_api_key_dict=None, response=_agen(chunks), request_data=data)]


def _parse_sse(chunks):
    raw = "".join(c.decode() if isinstance(c, bytes) else c for c in chunks)
    events = []
    for block in raw.split("\n\n"):
        for line in block.split("\n"):
            if line.startswith("data: "):
                events.append(json.loads(line[6:]))
    return events


def _joined(events, field="text"):
    return "".join(e["delta"].get(field, "") for e in events if e["type"] == "content_block_delta")


def _split(s, size):
    return [s[i:i + size] for i in range(0, len(s), size)]


async def test_stream_restores_fake_split_across_deltas_and_byte_chunks(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    text = f"Your token is {fake}. Done gh"
    raw = "".join(_sse(e) for e in _text_stream_events(_split(text, 3)))
    chunks = [c.encode() for c in _split(raw, 17)]

    out = await _collect(mw, chunks, data)

    assert all(isinstance(c, bytes) for c in out)
    events = _parse_sse(out)
    assert _joined(events) == f"Your token is {GH_PAT}. Done gh"
    types_ = [e["type"] for e in events]
    assert types_[-2:] == ["content_block_stop", "message_stop"]
    assert mw.pending_calls() == 0


async def test_stream_restores_tool_input_json_deltas(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    partial = json.dumps({"cmd": f"echo {fake}"})
    events = [
        {"type": "content_block_start", "index": 1,
         "content_block": {"type": "tool_use", "id": "t1", "name": "sh", "input": {}}},
        *[{"type": "content_block_delta", "index": 1,
           "delta": {"type": "input_json_delta", "partial_json": p}} for p in _split(partial, 5)],
        {"type": "content_block_stop", "index": 1},
    ]

    out = await _collect(mw, [_sse(e).encode() for e in events], data)

    assert json.loads(_joined(_parse_sse(out), "partial_json")) == {"cmd": f"echo {GH_PAT}"}


async def test_stream_leaves_thinking_deltas_alone(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    events = [
        {"type": "content_block_start", "index": 0, "content_block": {"type": "thinking", "thinking": ""}},
        {"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": fake}},
        {"type": "content_block_stop", "index": 0},
    ]

    out = await _collect(mw, [_sse(e).encode() for e in events], data)

    assert _joined(_parse_sse(out), "thinking") == fake


async def test_stream_restores_dict_events(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)

    out = await _collect(mw, _text_stream_events(_split(f"x {fake} y", 4)), data)

    assert all(isinstance(e, dict) for e in out)
    assert _joined(out) == f"x {GH_PAT} y"


async def test_stream_without_mapping_passes_chunks_through(mw):
    chunks = [b"event: ping\ndata: {}\n\n", "anything"]

    out = await _collect(mw, chunks, {"litellm_call_id": "unknown"})

    assert out == chunks
    assert out[0] is chunks[0]


def _chat_chunk(content=None, args=None, finish=None):
    tool_calls = None
    if args is not None:
        tool_calls = [SimpleNamespace(index=0, id=None, function=SimpleNamespace(name=None, arguments=args))]
    delta = SimpleNamespace(content=content, tool_calls=tool_calls)
    return SimpleNamespace(choices=[SimpleNamespace(index=0, delta=delta, finish_reason=finish)])


async def test_stream_restores_chat_completion_chunks(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    pieces = _split(f"key {fake} then gh", 4)
    chunks = [_chat_chunk(content=p) for p in pieces] + [_chat_chunk(finish="stop")]

    out = await _collect(mw, chunks, data)

    text = "".join(c.choices[0].delta.content or "" for c in out)
    assert text == f"key {GH_PAT} then gh"
    assert chunks[1].choices[0].delta.content == pieces[1]


async def test_stream_restores_chat_tool_call_arguments(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    pieces = _split(json.dumps({"cmd": fake}), 6)
    chunks = [_chat_chunk(args=p) for p in pieces] + [_chat_chunk(finish="tool_calls")]

    out = await _collect(mw, chunks, data)

    args = "".join(
        tc.function.arguments
        for c in out for tc in (c.choices[0].delta.tool_calls or []))
    assert json.loads(args) == {"cmd": GH_PAT}


async def test_mapping_expires(mod, monkeypatch):
    now = [1000.0]
    monkeypatch.setattr(mod.time, "monotonic", lambda: now[0])
    mw = mod.SecretMaskingMiddleware(key=b"k", ttl_seconds=60)

    await _mask(mw, GH_PAT, "old")
    now[0] += 61
    await _mask(mw, GH_PAT, "new")

    assert mw.pending_calls() == 1


def test_production_instance_is_exposed(mod):
    assert isinstance(mod.secret_masking, mod.SecretMaskingMiddleware)


async def test_failed_call_drops_mapping(mw):
    data = await _mask(mw, GH_PAT)

    await mw.async_post_call_failure_hook(
        request_data=data, original_exception=RuntimeError("x"), user_api_key_dict=None)

    assert mw.pending_calls() == 0


async def test_stream_restore_error_fails_open(mw, mod, monkeypatch, fake_litellm):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    head = {"type": "content_block_delta", "index": 0,
            "delta": {"type": "text_delta", "text": "key " + fake[:10]}}
    process = mod._StreamRestorer.process

    def flaky(self, chunk):
        if chunk == "boom":
            raise RuntimeError("restore bug")
        return process(self, chunk)

    monkeypatch.setattr(mod._StreamRestorer, "process", flaky)

    out = await _collect(mw, [head, "boom", "after"], data)

    assert out[0]["delta"]["text"] == "key "
    assert out[1]["delta"]["text"] == fake[:10]
    assert out[2:] == ["boom", "after"]
    assert fake_litellm.verbose_proxy_logger.warnings
    assert mw.pending_calls() == 0
