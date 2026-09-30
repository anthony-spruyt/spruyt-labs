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
    custom_logger = types.ModuleType("litellm.integrations.custom_logger")
    custom_logger.CustomLogger = type("CustomLogger", (), {})

    class Logger:
        def __init__(self):
            self.warnings = []

        def warning(self, *args, **kwargs):
            self.warnings.append((args, kwargs))

    logging.verbose_proxy_logger = Logger()
    monkeypatch.setitem(sys.modules, "litellm", litellm)
    monkeypatch.setitem(sys.modules, "litellm._logging", logging)
    monkeypatch.setitem(sys.modules, "litellm.integrations", types.ModuleType("litellm.integrations"))
    monkeypatch.setitem(sys.modules, "litellm.integrations.custom_logger", custom_logger)
    return logging


@pytest.fixture
def mod():
    sys.modules.pop("secret_masking", None)
    sys.modules.pop("pipeline", None)
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


async def test_masks_pgp_private_key_block(mw):
    begin = "-----BEGIN PGP " + "PRIVATE KEY BLOCK-----"
    end = "-----END PGP " + "PRIVATE KEY BLOCK-----"
    body = "\n\nlQOYBF7xQ2kBCADc9Qm4Zp1Rv8TnK3sW6yH0jL5aB2cD7eF9gI1kM3oP5qS\n=Ab3C\n"
    key = begin + body + end

    fake = _user_text(await _mask(mw, key))

    assert fake != key
    assert fake.startswith(begin)
    assert fake.endswith(end)
    assert _classes(fake) == _classes(key)


@pytest.mark.parametrize("line", [PEM_BEGIN, "-----BEGIN PGP " + "PRIVATE KEY BLOCK-----"], ids=["pem", "pgp"])
async def test_many_unterminated_pem_headers_mask_quickly(mw, line):
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


@pytest.mark.parametrize("escape", ["\\n", "\\t", "\\r", "\\b", "\\f", "\\u00a0"])
async def test_masks_secret_after_json_escape(mw, escape):
    text = '{"c": "line1' + escape + GH_PAT + '"}'

    assert GH_PAT not in _user_text(await _mask(mw, text))


async def test_masks_pem_after_json_newline_escape(mw):
    text = json.dumps({"cert": "cert\n" + PEM})

    out = _user_text(await _mask(mw, text))

    assert "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7" not in out


@pytest.mark.parametrize("text", ["n" + GH_PAT, "u00a0" + GH_PAT], ids=["n", "u00a0"])
async def test_escape_letters_without_backslash_still_guard(mw, text):
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


@pytest.mark.parametrize("call_type", ["aresponses", "responses"])
async def test_masks_responses_input_and_instructions(mw, call_type):
    data = {
        "litellm_call_id": "call-1",
        "instructions": f"env: {GH_PAT}",
        "input": [
            {"type": "message", "role": "user", "content": [{"type": "input_text", "text": GOOGLE}]},
            {"type": "function_call", "call_id": "c1", "name": "sh", "arguments": json.dumps({"k": SL_KEY})},
            {"type": "function_call_output", "call_id": "c1", "output": f"token={GH_PAT_2}"},
        ],
    }

    out = await mw.async_pre_call_hook(None, None, data, call_type)

    dumped = json.dumps(out)
    for secret in (GH_PAT, GOOGLE, SL_KEY, GH_PAT_2):
        assert secret not in dumped


async def test_does_not_touch_responses_media_urls_or_reasoning(mw):
    image = {"type": "input_image", "image_url": "https://x.test/a.png?sig=" + GH_PAT, "detail": "auto"}
    file_ = {"type": "input_file", "file_url": "https://x.test/a.pdf?sig=" + GH_PAT,
             "file_data": "https://x.test/b.pdf?sig=" + GH_PAT}
    reasoning = {"type": "reasoning", "summary": [{"type": "summary_text", "text": GH_PAT}],
                 "encrypted_content": "gAAAA/" + GOOGLE}
    data = {
        "litellm_call_id": "call-1",
        "input": [
            copy.deepcopy(reasoning),
            {"type": "message", "role": "user",
             "content": [copy.deepcopy(image), copy.deepcopy(file_), {"type": "input_text", "text": GH_PAT}]},
        ],
    }

    out = await mw.async_pre_call_hook(None, None, data, "aresponses")

    assert out["input"][0] == reasoning
    assert out["input"][1]["content"][:2] == [image, file_]
    assert out["input"][1]["content"][2]["text"] != GH_PAT


async def test_masks_responses_string_input(mw):
    data = {"litellm_call_id": "call-1", "input": f"use {GH_PAT}"}

    out = await mw.async_pre_call_hook(None, None, data, "aresponses")

    assert GH_PAT not in out["input"]


@pytest.mark.parametrize("call_type", ["atext_completion", "text_completion"])
@pytest.mark.parametrize("prompt", [f"use {GH_PAT}", [f"use {GH_PAT}", "other"]], ids=["str", "list"])
async def test_masks_text_completion_prompt(mw, call_type, prompt):
    data = {"litellm_call_id": "call-1", "prompt": prompt}

    out = await mw.async_pre_call_hook(None, None, data, call_type)

    assert GH_PAT not in json.dumps(out)


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


async def test_restores_text_completion_response(mw):
    data = await _mask(mw, f"use {GH_PAT}")
    fake = _user_text(data).split()[1]
    response = SimpleNamespace(choices=[SimpleNamespace(index=0, text=f"ok {fake}", finish_reason="stop")])

    out = await mw.async_post_call_success_hook(data=data, user_api_key_dict=None, response=response)

    assert out.choices[0].text == f"ok {GH_PAT}"
    assert response.choices[0].text == f"ok {fake}"


def _responses_output(fake):
    return [
        {"type": "reasoning", "summary": [{"type": "summary_text", "text": fake}]},
        SimpleNamespace(type="message", role="assistant", content=[
            SimpleNamespace(type="output_text", text=f"ok {fake}", annotations=[]),
            {"type": "refusal", "refusal": f"no {fake}"},
        ]),
        SimpleNamespace(type="function_call", call_id="c1", name="sh", arguments=json.dumps({"cmd": fake})),
        {"type": "custom_tool_call", "call_id": "c2", "name": "patch", "input": f"echo {fake}"},
    ]


async def test_restores_responses_api_response(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    response = SimpleNamespace(id="resp_1", output=_responses_output(fake))

    out = await mw.async_post_call_success_hook(data=data, user_api_key_dict=None, response=response)

    assert out.output[0]["summary"][0]["text"] == fake
    assert out.output[1].content[0].text == f"ok {GH_PAT}"
    assert out.output[1].content[1]["refusal"] == f"no {GH_PAT}"
    assert json.loads(out.output[2].arguments) == {"cmd": GH_PAT}
    assert out.output[3]["input"] == f"echo {GH_PAT}"
    assert response.output[1].content[0].text == f"ok {fake}"


async def test_restores_responses_api_response_with_non_string_part_type(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    output = [{"type": "message", "content": [{"type": ["x"]}, {"type": "output_text", "text": fake}]}]

    out = await mw.async_post_call_success_hook(
        data=data, user_api_key_dict=None, response=SimpleNamespace(id="r", output=output))

    assert out.output[0]["content"][1]["text"] == GH_PAT


async def test_chat_response_without_fakes_is_not_copied(mw, mod, monkeypatch):
    data = await _mask(mw, f"use {GH_PAT}")
    message = SimpleNamespace(
        content="nothing here",
        tool_calls=[SimpleNamespace(function=SimpleNamespace(name="sh", arguments='{"a": 1}'))],
    )
    response = SimpleNamespace(choices=[SimpleNamespace(message=message)])

    def no_copy(_):
        raise AssertionError("deepcopy")

    monkeypatch.setattr(mod.copy, "deepcopy", no_copy)

    out = await mw.async_post_call_success_hook(data=data, user_api_key_dict=None, response=response)

    assert out is None or out is response
    assert mw.pending_calls() == 0


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


async def test_stream_tolerates_non_string_delta_type(mw, fake_litellm):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    odd = {"type": "content_block_delta", "index": 0, "delta": {"type": ["x"]}}

    out = await _collect(mw, [odd, *_text_stream_events(_split(fake, 4))], data)

    assert _joined(out) == GH_PAT
    assert not [w for w in fake_litellm.verbose_proxy_logger.warnings if "failed open" in w[0][0]]


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


def _text_chunk(text=None, finish=None, index=0):
    return SimpleNamespace(choices=[SimpleNamespace(index=index, text=text, finish_reason=finish)])


async def test_stream_restores_text_completion_chunks(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    pieces = _split(f"key {fake} then gh", 4)
    chunks = [_text_chunk(p) for p in pieces] + [_text_chunk(finish="stop")]

    out = await _collect(mw, chunks, data)

    assert "".join(c.choices[0].text or "" for c in out) == f"key {GH_PAT} then gh"
    assert chunks[1].choices[0].text == pieces[1]


async def test_text_completion_stream_end_flushes_held_text(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)

    out = await _collect(mw, [_text_chunk("key "), _text_chunk(fake[:10])], data)

    assert "".join(c.choices[0].text or "" for c in out) == "key " + fake[:10]


def _resp_event(kind, **fields):
    return SimpleNamespace(type=kind, **fields)


def _resp_text_events(fake, text):
    pieces = _split(text, 4)
    message = SimpleNamespace(type="message", role="assistant", content=[
        SimpleNamespace(type="output_text", text=text, annotations=[])])
    return [
        _resp_event("response.created", response=SimpleNamespace(id="r1", output=[])),
        *[_resp_event("response.output_text.delta", item_id="m1", output_index=0, content_index=0, delta=p)
          for p in pieces],
        _resp_event("response.output_text.done", item_id="m1", output_index=0, content_index=0, text=text),
        _resp_event("response.content_part.done", item_id="m1", output_index=0, content_index=0,
                    part=SimpleNamespace(type="output_text", text=text, annotations=[])),
        _resp_event("response.output_item.done", output_index=0, item=message),
        _resp_event("response.completed", response=SimpleNamespace(id="r1", output=[copy.deepcopy(message)])),
    ]


def _resp_deltas(out, kind="response.output_text.delta"):
    return "".join(_get_field(e, "delta") for e in out if _get_field(e, "type") == kind)


def _get_field(obj, key):
    return obj.get(key) if isinstance(obj, dict) else getattr(obj, key, None)


async def test_stream_restores_responses_api_events(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    events = _resp_text_events(fake, f"key {fake} then gh")

    out = await _collect(mw, events, data)

    real = f"key {GH_PAT} then gh"
    by_type = {e.type: e for e in out}
    assert _resp_deltas(out) == real
    assert by_type["response.output_text.done"].text == real
    assert by_type["response.content_part.done"].part.text == real
    assert by_type["response.output_item.done"].item.content[0].text == real
    assert by_type["response.completed"].response.output[0].content[0].text == real
    assert [e.type for e in out][-4:] == [e.type for e in events][-4:]
    assert events[-1].response.output[0].content[0].text == f"key {fake} then gh"


async def test_stream_restores_responses_function_call_arguments(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    args = json.dumps({"cmd": fake})
    events = [
        *[_resp_event("response.function_call_arguments.delta", item_id="f1", output_index=1, delta=p)
          for p in _split(args, 5)],
        _resp_event("response.function_call_arguments.done", item_id="f1", output_index=1, arguments=args),
    ]

    out = await _collect(mw, events, data)

    assert json.loads(_resp_deltas(out, "response.function_call_arguments.delta")) == {"cmd": GH_PAT}
    assert json.loads(out[-1].arguments) == {"cmd": GH_PAT}


async def test_stream_restores_responses_sse_bytes(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    text = f"key {fake} then gh"
    events = [{"type": "response.output_text.delta", "item_id": "m1", "output_index": 0,
               "content_index": 0, "delta": p} for p in _split(text, 3)]
    events.append({"type": "response.output_text.done", "item_id": "m1", "output_index": 0,
                   "content_index": 0, "text": text})
    raw = "".join(_sse(e) for e in events)

    out = await _collect(mw, [c.encode() for c in _split(raw, 17)], data)

    parsed = _parse_sse(out)
    assert _resp_deltas(parsed) == f"key {GH_PAT} then gh"
    assert parsed[-1]["text"] == f"key {GH_PAT} then gh"


async def test_responses_stream_end_flushes_held_text(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    events = [_resp_event("response.output_text.delta", item_id="m1", output_index=0, content_index=0, delta=d)
              for d in ("key ", fake[:10])]

    out = await _collect(mw, events, data)

    assert _resp_deltas(out) == "key " + fake[:10]


async def test_stream_leaves_responses_reasoning_alone(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    event = _resp_event("response.reasoning_summary_text.delta", item_id="r1", output_index=0, delta=fake)

    out = await _collect(mw, [event], data)

    assert out == [event]


async def test_mapping_expires(mod, monkeypatch):
    now = [1000.0]
    monkeypatch.setattr(mod.time, "monotonic", lambda: now[0])
    mw = mod.SecretMaskingMiddleware(key=b"k", ttl_seconds=60)

    await _mask(mw, GH_PAT, "old")
    now[0] += 61
    await _mask(mw, GH_PAT, "new")

    assert mw.pending_calls() == 1


async def test_unmasked_request_still_prunes_expired_mappings(mod, monkeypatch):
    now = [1000.0]
    monkeypatch.setattr(mod.time, "monotonic", lambda: now[0])
    mw = mod.SecretMaskingMiddleware(key=b"k", ttl_seconds=60)

    await _mask(mw, GH_PAT, "old")
    now[0] += 61
    await _mask(mw, "nothing secret", "new")

    assert mw.pending_calls() == 0


async def test_pending_calls_are_capped(mod):
    mw = mod.SecretMaskingMiddleware(key=b"k", max_calls=3)

    for i in range(5):
        await _mask(mw, GH_PAT, f"call-{i}")

    assert mw.pending_calls() == 3


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


async def test_stream_end_with_truncated_utf8_fails_open(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    head = _sse({"type": "content_block_delta", "index": 0,
                 "delta": {"type": "text_delta", "text": "key " + fake[:10]}}).encode()
    tail = b"event: x\ndata: \xe2\x82"

    out = await _collect(mw, [head, tail], data)

    raw = b"".join(out)
    assert raw.endswith(tail)
    assert _joined(_parse_sse([raw[:-len(tail)].decode()])) == "key " + fake[:10]
    assert mw.pending_calls() == 0


async def test_sse_fail_open_does_not_drop_or_duplicate_bytes(mw, mod, monkeypatch):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    texts = ["key " + fake[:10], " middle", " boom", " end"]
    raw = [_sse({"type": "content_block_delta", "index": 0,
                 "delta": {"type": "text_delta", "text": t}}) for t in texts]
    half = len(raw[1]) // 2
    chunks = [(raw[0] + raw[1][:half]).encode(), (raw[1][half:] + raw[2]).encode(), raw[3].encode()]
    real_events = mod._StreamRestorer._events

    def flaky(self, event):
        if event.get("delta", {}).get("text") == " boom":
            raise RuntimeError("restore bug")
        return real_events(self, event)

    monkeypatch.setattr(mod._StreamRestorer, "_events", flaky)

    out = await _collect(mw, chunks, data)

    assert _joined(_parse_sse(out)) == "".join(texts)


async def test_chat_stream_end_flush_does_not_repeat_last_delta(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)

    out = await _collect(mw, [_chat_chunk(content="key "), _chat_chunk(content=fake[:10])], data)

    text = "".join(c.choices[0].delta.content or "" for c in out if c.choices)
    assert text == "key " + fake[:10]


async def test_chat_stream_end_flush_after_usage_chunk(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    usage = SimpleNamespace(choices=[], usage={"total_tokens": 3})

    out = await _collect(mw, [_chat_chunk(content="key " + fake[:10]), usage], data)

    text = "".join(c.choices[0].delta.content or "" for c in out if c.choices)
    assert text == "key " + fake[:10]
    assert sum(1 for c in out if getattr(c, "usage", None)) == 1


async def test_chat_finish_chunk_keeps_its_own_tool_call_deltas(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    first = _chat_chunk(args='{"a": "')
    last = _chat_chunk(args=fake[:10], finish="tool_calls")
    last.choices[0].delta.tool_calls.append(
        SimpleNamespace(index=1, id="t2", function=SimpleNamespace(name="other", arguments='{"b": 1}')))

    out = await _collect(mw, [first, last], data)

    args = {}
    for c in out:
        for tc in c.choices[0].delta.tool_calls or []:
            args[tc.index] = args.get(tc.index, "") + tc.function.arguments
    assert args == {0: '{"a": "' + fake[:10], 1: '{"b": 1}'}


async def test_does_not_touch_data_urls_or_input_audio(mw):
    blob = "iVBORw0KGgo/" + GOOGLE + "+rest=="
    image = {"type": "image_url", "image_url": {"url": "data:image/png;base64," + blob}}
    audio = {"type": "input_audio", "input_audio": {"data": blob, "format": "wav"}}
    file_ = {"type": "file", "file": {"file_data": "data:application/pdf;base64," + blob}}
    data = {
        "litellm_call_id": "call-1",
        "messages": [{"role": "user", "content": [image, audio, file_, {"type": "text", "text": GH_PAT}]}],
    }

    out = await mw.async_pre_call_hook(None, None, data, "acompletion")

    content = out["messages"][0]["content"]
    assert content[:3] == [image, audio, file_]
    assert content[3]["text"] != GH_PAT


AWS_TEMP = "AS" + "IA" + "QW3ERT5YU7IO9PAS"
PRESIGNED = ("https://bucket.s3.amazonaws.com/cat.png?X-Amz-Algorithm=AWS4-HMAC-SHA256"
             "&X-Amz-Credential=" + AWS_TEMP + "%2F20260930%2Fus-east-1%2Fs3%2Faws4_request")


async def test_does_not_touch_remote_media_urls(mw):
    blocks = [
        {"type": "image_url", "image_url": {"url": PRESIGNED, "detail": "high"}},
        {"type": "image_url", "image_url": PRESIGNED},
        {"type": "file", "file": {"file_id": PRESIGNED}},
        {"type": "image", "source": {"type": "url", "url": PRESIGNED}},
        {"type": "document", "source": {"type": "url", "url": PRESIGNED}},
    ]
    data = {
        "litellm_call_id": "call-1",
        "messages": [{"role": "user", "content": [*copy.deepcopy(blocks), {"type": "text", "text": GH_PAT}]}],
    }

    out = await mw.async_pre_call_hook(None, None, data, "acompletion")

    content = out["messages"][0]["content"]
    assert content[:-1] == blocks
    assert content[-1]["text"] != GH_PAT


async def test_restore_does_not_touch_remote_media_urls(mw):
    data = await _mask(mw, AWS_TEMP)
    fake = _user_text(data)
    url = PRESIGNED.replace(AWS_TEMP, fake)
    response = {"content": [{"type": "image", "source": {"type": "url", "url": url}},
                            {"type": "text", "text": fake}]}

    out = await mw.async_post_call_success_hook(data=data, user_api_key_dict=None, response=response)

    assert out["content"][0]["source"]["url"] == url
    assert out["content"][1]["text"] == AWS_TEMP


async def test_concurrent_calls_sharing_an_id_both_restore(mw):
    first = await _mask(mw, GH_PAT, "shared")
    second = await _mask(mw, GH_PAT_2, "shared")
    fake1, fake2 = _user_text(first), _user_text(second)

    out1 = await mw.async_post_call_success_hook(
        data=first, user_api_key_dict=None, response={"content": [{"type": "text", "text": fake1}]})
    out2 = await mw.async_post_call_success_hook(
        data=second, user_api_key_dict=None, response={"content": [{"type": "text", "text": fake2}]})

    assert out1["content"][0]["text"] == GH_PAT
    assert out2["content"][0]["text"] == GH_PAT_2
    assert mw.pending_calls() == 0


def test_warnings_use_the_pipeline_logger(mod):
    assert mod._log_warning is sys.modules["pipeline"].MiddlewarePipeline._log_warning


def test_missing_salt_logs_warning(mod, monkeypatch, fake_litellm):
    monkeypatch.delenv("LITELLM_SALT_KEY", raising=False)

    mod._key_from_env()

    assert any("LITELLM_SALT_KEY" in w[0][0] for w in fake_litellm.verbose_proxy_logger.warnings)


async def test_data_prefixed_text_is_still_masked(mw):
    data = await _mask(mw, "data:\n  GITHUB_TOKEN: " + GH_PAT)

    assert GH_PAT not in _user_text(data)


async def test_unmasked_call_sharing_an_id_does_not_release_the_other(mw):
    first = await _mask(mw, GH_PAT, "shared")
    second = await _mask(mw, "no secrets here", "shared")
    fake = _user_text(first)

    await mw.async_post_call_success_hook(data=second, user_api_key_dict=None, response={"t": "hi"})
    out = await mw.async_post_call_success_hook(
        data=first, user_api_key_dict=None, response={"content": [{"type": "text", "text": fake}]})

    assert out["content"][0]["text"] == GH_PAT
    assert mw.pending_calls() == 0


async def test_unmasked_call_first_sharing_an_id_does_not_release_the_other(mw):
    second = await _mask(mw, "no secrets here", "shared")
    first = await _mask(mw, GH_PAT, "shared")
    fake = _user_text(first)

    await mw.async_post_call_success_hook(data=second, user_api_key_dict=None, response={"t": "hi"})
    out = await mw.async_post_call_success_hook(
        data=first, user_api_key_dict=None, response={"content": [{"type": "text", "text": fake}]})

    assert out["content"][0]["text"] == GH_PAT
    assert mw.pending_calls() == 0


async def test_stream_error_then_failure_hook_releases_once(mw):
    first = await _mask(mw, GH_PAT, "shared")
    second = await _mask(mw, GH_PAT_2, "shared")
    fake = _user_text(first)

    async def broken():
        yield {"type": "message_start"}
        raise ValueError("provider down")

    with pytest.raises(ValueError):
        async for _ in mw.async_post_call_streaming_iterator_hook(response=broken(), request_data=second):
            pass
    await mw.async_post_call_failure_hook(request_data=second)
    out = await mw.async_post_call_success_hook(
        data=first, user_api_key_dict=None, response={"content": [{"type": "text", "text": fake}]})

    assert out["content"][0]["text"] == GH_PAT
    assert mw.pending_calls() == 0


async def test_chat_stream_end_flush_keeps_each_choice(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)

    def chunk(index, content):
        delta = SimpleNamespace(content=content, tool_calls=None)
        return SimpleNamespace(choices=[SimpleNamespace(index=index, delta=delta, finish_reason=None)])

    out = await _collect(mw, [chunk(1, "b " + fake[:10]), chunk(0, "a")], data)

    text = {}
    for c in out:
        for ch in c.choices:
            text[ch.index] = text.get(ch.index, "") + (ch.delta.content or "")
    assert text == {0: "a", 1: "b " + fake[:10]}


async def test_masks_request_with_non_string_type_fields(mw):
    schema = {"type": "object", "properties": {"x": {"type": ["string", "null"]}}}
    data = {
        "litellm_call_id": "call-1",
        "messages": [
            {"role": "assistant", "content": [
                {"type": "tool_use", "id": "t1", "name": "sh", "input": {"schema": schema, "t": {"type": {}}}}]},
            {"role": "user", "content": [{"type": "text", "text": GH_PAT}]},
        ],
    }

    out = await mw.async_pre_call_hook(None, None, data, "anthropic_messages")

    assert GH_PAT not in json.dumps(out)


async def test_restores_response_with_non_string_type_fields(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    response = {"content": [{"type": "tool_use", "input": {"type": ["string", "null"], "v": fake}}]}

    out = await mw.async_post_call_success_hook(data=data, user_api_key_dict=None, response=response)

    assert out["content"][0]["input"]["v"] == GH_PAT


async def test_failure_hook_releases_after_litellm_drops_the_logging_obj(mw):
    request = _request(GH_PAT)
    request["litellm_logging_obj"] = object()
    request["proxy_server_request"] = {}
    data = await mw.async_pre_call_hook(None, None, request, "anthropic_messages")
    data.pop("litellm_logging_obj")

    await mw.async_post_call_failure_hook(request_data=data)

    assert mw.pending_calls() == 0


async def test_stream_joins_multi_line_sse_data(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    event = {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "key " + fake}}
    lines = json.dumps(event, indent=1).split("\n")
    block = "event: content_block_delta\n" + "\n".join("data: " + line for line in lines) + "\n\n"

    out = await _collect(mw, [block.encode()], data)

    assert fake not in b"".join(out).decode()
    assert _joined(_parse_sse(out)) == "key " + GH_PAT


async def test_chat_stream_flushes_held_text_before_usage_chunk(mw):
    data = await _mask(mw, GH_PAT)
    fake = _user_text(data)
    usage = SimpleNamespace(choices=[], usage={"total_tokens": 3})

    out = await _collect(mw, [_chat_chunk(content="key " + fake[:10]), usage], data)

    assert out[-1] is usage
    assert "".join(c.choices[0].delta.content or "" for c in out if c.choices) == "key " + fake[:10]


class _CountingPattern:
    def __init__(self, pattern):
        self.pattern = pattern
        self.scanned = []

    def sub(self, repl, text):
        self.scanned.append(text)
        return self.pattern.sub(repl, text)


@pytest.fixture
def scans(mod, monkeypatch):
    counting = _CountingPattern(mod._SECRET_RE)
    monkeypatch.setattr(mod, "_SECRET_RE", counting)
    return counting.scanned


async def test_large_clean_text_is_scanned_once(mw, scans):
    history = "lorem ipsum dolor " * 1000

    for call_id in ("call-1", "call-2", "call-3"):
        await _mask(mw, history, call_id)

    assert scans.count(history) == 1


async def test_large_text_with_secret_is_masked_every_time(mw):
    history = "lorem ipsum dolor " * 1000 + GH_PAT

    for call_id in ("call-1", "call-2"):
        assert GH_PAT not in _user_text(await _mask(mw, history, call_id))


async def test_small_text_is_not_cached(mw, scans):
    for call_id in ("call-1", "call-2"):
        await _mask(mw, "short clean text", call_id)

    assert scans.count("short clean text") == 2


async def test_clean_text_cache_is_bounded(mod, scans):
    mw = mod.SecretMaskingMiddleware(key=b"k", clean_cache_size=3)
    texts = [f"clean {i} " * 1000 for i in range(5)]

    for i, text in enumerate(texts):
        await _mask(mw, text, f"call-{i}")
    await _mask(mw, texts[0], "again")

    assert scans.count(texts[0]) == 2


async def _finish(mw, data, text="ok"):
    await mw.async_post_call_success_hook(
        data=data, user_api_key_dict=None, response={"content": [{"type": "text", "text": text}]})


async def _earlier_fake(mw, secret=GH_PAT, call_id="turn-1", user=None):
    data = await mw.async_pre_call_hook(user, None, _request(secret, call_id), "anthropic_messages")
    fake = _user_text(data)
    await mw.async_post_call_success_hook(data=data, user_api_key_dict=user, response={"t": "ok"})
    return fake


async def test_stale_fake_from_earlier_turn_is_restored(mw):
    fake = await _earlier_fake(mw)
    data = await _mask(mw, "continue", "turn-2")

    out = await mw.async_post_call_success_hook(
        data=data, user_api_key_dict=None, response={"content": [{"type": "text", "text": f"use {fake}"}]})

    assert mw.pending_calls() == 0
    assert out["content"][0]["text"] == f"use {GH_PAT}"


async def test_stale_fake_is_restored_alongside_this_calls_fakes(mw):
    old = await _earlier_fake(mw)
    data = await _mask(mw, GH_PAT_2, "turn-2")
    new = _user_text(data)

    out = await mw.async_post_call_success_hook(
        data=data, user_api_key_dict=None, response={"content": [{"type": "text", "text": f"{old} {new}"}]})

    assert out["content"][0]["text"] == f"{GH_PAT} {GH_PAT_2}"


async def test_stale_fake_is_restored_in_stream(mw):
    fake = await _earlier_fake(mw)
    data = await _mask(mw, "continue", "turn-2")

    out = await _collect(mw, _text_stream_events(_split(f"x {fake} y", 4)), data)

    assert _joined(out) == f"x {GH_PAT} y"


async def test_stale_fake_is_not_restored_for_another_key(mw):
    fake = await _earlier_fake(mw, user=SimpleNamespace(api_key="hash-a"))
    other = SimpleNamespace(api_key="hash-b")
    data = await mw.async_pre_call_hook(other, None, _request("continue", "turn-2"), "anthropic_messages")

    out = await mw.async_post_call_success_hook(
        data=data, user_api_key_dict=other, response={"content": [{"type": "text", "text": fake}]})

    assert out is None or out["content"][0]["text"] == fake


async def test_stale_fakes_expire(mod, monkeypatch):
    now = [1000.0]
    monkeypatch.setattr(mod.time, "monotonic", lambda: now[0])
    mw = mod.SecretMaskingMiddleware(key=b"k", ttl_seconds=60)
    fake = await _earlier_fake(mw)
    now[0] += 61
    data = await _mask(mw, "continue", "turn-2")

    out = await mw.async_post_call_success_hook(
        data=data, user_api_key_dict=None, response={"content": [{"type": "text", "text": fake}]})

    assert out is None or out["content"][0]["text"] == fake
    assert not mw.wants_stream(data)


async def test_stale_fakes_are_capped(mod):
    mw = mod.SecretMaskingMiddleware(key=b"k", max_known_fakes=1)
    first = await _earlier_fake(mw, GH_PAT, "turn-1")
    await _earlier_fake(mw, GH_PAT_2, "turn-2")
    data = await _mask(mw, "continue", "turn-3")

    out = await mw.async_post_call_success_hook(
        data=data, user_api_key_dict=None, response={"content": [{"type": "text", "text": first}]})

    assert out is None or out["content"][0]["text"] == first


async def test_own_fakes_restore_even_when_evicted_from_the_global_map(mod):
    mw = mod.SecretMaskingMiddleware(key=b"k", max_known_fakes=1)
    data = await _mask(mw, f"{GH_PAT} {GH_PAT_2}")
    a, b = _user_text(data).split()

    out = await mw.async_post_call_success_hook(
        data=data, user_api_key_dict=None, response={"content": [{"type": "text", "text": f"{a} {b}"}]})

    assert out["content"][0]["text"] == f"{GH_PAT} {GH_PAT_2}"


async def test_wants_stream(mw):
    clean = await _mask(mw, "nothing here", "clean")
    assert not mw.wants_stream(clean)

    masked = await _mask(mw, GH_PAT, "masked")
    assert mw.wants_stream(masked)

    await _finish(mw, masked)
    assert mw.wants_stream(await _mask(mw, "nothing here", "later"))


async def test_stream_with_many_known_fakes_stays_fast(mod):
    mw = mod.SecretMaskingMiddleware(key=b"k")
    secrets = [GH_PAT[:-6] + f"{i:06d}" for i in range(1500)]
    await _earlier_fake(mw, " ".join(secrets))
    data = await _mask(mw, "continue", "turn-2")
    deltas = _split("plain streamed words and some ghp_ looking text " * 400, 3)

    start = time.monotonic()
    out = await _collect(mw, _text_stream_events(deltas), data)

    assert time.monotonic() - start < 0.3
    assert _joined(out) == "".join(deltas)


async def test_masks_and_restores_compact_responses(mw):
    data = {"litellm_call_id": "call-1", "instructions": f"env {GH_PAT}",
            "input": [{"type": "message", "role": "user", "content": [{"type": "input_text", "text": GOOGLE}]}]}

    out = await mw.async_pre_call_hook(None, None, data, "acompact_responses")

    dumped = json.dumps(out)
    assert GH_PAT not in dumped and GOOGLE not in dumped
    fake = out["input"][0]["content"][0]["text"]
    response = SimpleNamespace(id="r", output=[{"type": "message", "content": [{"type": "output_text", "text": fake}]}])
    restored = await mw.async_post_call_success_hook(data=out, user_api_key_dict=None, response=response)
    assert restored.output[0]["content"][0]["text"] == GOOGLE


def _ws_frame(text):
    return json.dumps({"type": "response.create", "model": "gpt-x", "instructions": f"env {text}",
                       "input": [{"type": "message", "role": "user",
                                  "content": [{"type": "input_text", "text": text},
                                              {"type": "input_image", "image_url": "https://x.test/a?sig=" + text}]}]})


async def test_masks_responses_websocket_first_frame(mw):
    data = {"litellm_call_id": "call-1", "model": "gpt-x", "websocket": object(), "first_message": _ws_frame(GH_PAT)}

    out = await mw.async_pre_call_hook(None, None, data, "_aresponses_websocket")

    frame = json.loads(out["first_message"])
    assert GH_PAT not in frame["instructions"]
    assert frame["input"][0]["content"][0]["text"] != GH_PAT
    assert frame["input"][0]["content"][1]["image_url"].endswith(GH_PAT)
    assert frame["model"] == "gpt-x"


async def test_websocket_frame_that_is_not_json_is_left_alone(mw):
    data = {"litellm_call_id": "call-1", "first_message": "not json " + GH_PAT}

    out = await mw.async_pre_call_hook(None, None, data, "_aresponses_websocket")

    assert out["first_message"] == "not json " + GH_PAT


def _gemini_request():
    return {
        "litellm_call_id": "call-1",
        "systemInstruction": {"parts": [{"text": f"env {GH_PAT}"}]},
        "config": {"system_instruction": {"parts": [{"text": GOOGLE}]}, "temperature": 0.2},
        "contents": [
            {"role": "user", "parts": [
                {"text": f"key {SL_KEY}"},
                {"inlineData": {"mimeType": "image/png", "data": "iVBOR/" + GOOGLE + "+x"}},
                {"fileData": {"mimeType": "application/pdf", "fileUri": "https://x.test/f?sig=" + GH_PAT}},
            ]},
            {"role": "model", "parts": [
                {"text": f"saw {GH_PAT_2}", "thought": True},
                {"functionCall": {"name": "sh", "args": {"cmd": f"echo {GH_PAT_2}"}}, "thoughtSignature": "c2ln"},
            ]},
            {"role": "user", "parts": [{"functionResponse": {"name": "sh", "response": {"out": GH_PAT_2}}}]},
        ],
    }


@pytest.mark.parametrize("call_type", ["agenerate_content", "agenerate_content_stream"])
async def test_masks_google_generate_content(mw, call_type):
    original = _gemini_request()

    out = await mw.async_pre_call_hook(None, None, copy.deepcopy(original), call_type)

    assert GH_PAT not in json.dumps(out["systemInstruction"])
    assert GOOGLE not in json.dumps(out["config"]["system_instruction"])
    user, model, tool = out["contents"]
    assert SL_KEY not in user["parts"][0]["text"]
    assert user["parts"][1:] == original["contents"][0]["parts"][1:]
    assert model["parts"][0] == original["contents"][1]["parts"][0]
    assert GH_PAT_2 not in json.dumps(model["parts"][1]["functionCall"])
    assert model["parts"][1]["thoughtSignature"] == "c2ln"
    assert GH_PAT_2 not in json.dumps(tool)


async def test_gemini_dict_response_leaves_thought_parts_alone(mw):
    data = await mw.async_pre_call_hook(None, None, _gemini_request(), "agenerate_content")
    fake = _gemini_fake(data)
    response = {"candidates": [{"content": {"role": "model", "parts": [
        {"text": fake, "thought": True}, {"text": f"use {fake}"}]}}]}

    out = await mw.async_post_call_success_hook(data=data, user_api_key_dict=None, response=response)

    parts = out["candidates"][0]["content"]["parts"]
    assert parts[0]["text"] == fake
    assert parts[1]["text"] == f"use {SL_KEY}"


async def test_many_known_fakes_keep_calls_cheap(mod):
    mw = mod.SecretMaskingMiddleware(key=b"k")
    await _earlier_fake(mw, " ".join(GH_PAT[:-6] + f"{i:06d}" for i in range(2000)))
    reply = {"content": [{"type": "text", "text": "ordinary reply text ghp_ sk- " * 400}]}

    start = time.monotonic()
    for i in range(20):
        data = await _mask(mw, GH_PAT_2[:-6] + f"{i:06d}", f"turn-{i}")
        await mw.async_post_call_success_hook(data=data, user_api_key_dict=None, response=reply)

    assert time.monotonic() - start < 0.3


async def test_gemini_opaque_keys_do_not_leak_into_other_formats(mw):
    tool_input = {"thought": True, "note": GH_PAT, "inlineData": GOOGLE, "thoughtSignature": SL_KEY}
    data = {"litellm_call_id": "call-1", "messages": [{"role": "assistant", "content": [
        {"type": "tool_use", "id": "t1", "name": "sh", "input": tool_input}]}]}

    out = await mw.async_pre_call_hook(None, None, data, "anthropic_messages")

    dumped = json.dumps(out)
    for secret in (GH_PAT, GOOGLE, SL_KEY):
        assert secret not in dumped


async def test_gemini_function_args_with_opaque_key_names_are_masked(mw):
    data = {"litellm_call_id": "call-1", "contents": [{"role": "model", "parts": [
        {"functionCall": {"name": "sh", "args": {"thought": True, "inlineData": GH_PAT}}}]}]}

    out = await mw.async_pre_call_hook(None, None, data, "agenerate_content")

    assert GH_PAT not in json.dumps(out)


def _gemini_fake(mw_out):
    fake = mw_out["contents"][0]["parts"][0]["text"].split()[1]
    assert fake != SL_KEY
    return fake


async def test_restores_google_generate_content_response(mw):
    data = await mw.async_pre_call_hook(None, None, _gemini_request(), "agenerate_content")
    fake = _gemini_fake(data)
    part = SimpleNamespace(text=f"use {fake}", thought=None, function_call=None)
    call = {"functionCall": {"name": "sh", "args": {"cmd": fake, "n": 1}}}
    thought = {"text": fake, "thought": True}
    response = SimpleNamespace(candidates=[SimpleNamespace(index=0, content=SimpleNamespace(
        role="model", parts=[part, call, thought]))])

    out = await mw.async_post_call_success_hook(data=data, user_api_key_dict=None, response=response)

    parts = out.candidates[0].content.parts
    assert parts[0].text == f"use {SL_KEY}"
    assert parts[1]["functionCall"]["args"] == {"cmd": SL_KEY, "n": 1}
    assert parts[2]["text"] == fake
    assert part.text == f"use {fake}"


def _gemini_sse(text=None, finish=None, call=None):
    parts = []
    if text is not None:
        parts.append({"text": text})
    if call is not None:
        parts.append({"functionCall": call})
    candidate = {"content": {"role": "model", "parts": parts}, "index": 0}
    if finish:
        candidate["finishReason"] = finish
    return "data: " + json.dumps({"candidates": [candidate]}) + "\r\n\r\n"


def _gemini_parse(chunks):
    events = _parse_sse(chunks)
    text = "".join(p.get("text", "") for e in events for c in e.get("candidates", [])
                   for p in c["content"]["parts"])
    calls = [p["functionCall"] for e in events for c in e.get("candidates", []) for p in c["content"]["parts"]
             if "functionCall" in p]
    return events, text, calls


async def test_stream_restores_google_generate_content(mw):
    data = await mw.async_pre_call_hook(None, None, _gemini_request(), "agenerate_content_stream")
    fake = _gemini_fake(data)
    pieces = _split(f"key {fake} done", 5)
    raw = [_gemini_sse(p) for p in pieces]
    raw.append(_gemini_sse(call={"name": "sh", "args": {"cmd": fake}}, finish="STOP"))

    out = await _collect(mw, [r.encode() for r in raw], data)

    events, text, calls = _gemini_parse(out)
    assert text == f"key {SL_KEY} done"
    assert calls == [{"name": "sh", "args": {"cmd": SL_KEY}}]
    assert events[-1]["candidates"][0]["finishReason"] == "STOP"
    assert b"event:" not in b"".join(out)


async def test_google_stream_end_flushes_held_text(mw):
    data = await mw.async_pre_call_hook(None, None, _gemini_request(), "agenerate_content_stream")
    fake = _gemini_fake(data)

    out = await _collect(mw, [_gemini_sse("key ").encode(), _gemini_sse(fake[:10]).encode()], data)

    assert _gemini_parse(out)[1] == "key " + fake[:10]


def _proxy_server_with_counter():
    proxy_server = types.ModuleType("litellm.proxy.proxy_server")
    proxy_server.sent = []

    async def _try_provider_token_count(**kwargs):
        proxy_server.sent.append(kwargs)
        return "count"

    proxy_server._try_provider_token_count = _try_provider_token_count
    return proxy_server


async def test_provider_token_count_is_masked(mw, mod):
    proxy_server = _proxy_server_with_counter()
    mod.install_token_count_masking(mw, proxy_server)

    result = await proxy_server._try_provider_token_count(
        provider_counter=None, custom_llm_provider="anthropic", model_to_use="m",
        messages=[{"role": "user", "content": [{"type": "text", "text": GH_PAT}]}],
        contents=[{"role": "user", "parts": [{"text": GOOGLE}]}],
        deployment={"litellm_params": {"api_key": "provider-key"}}, request_model="m",
        tools=[{"name": "t", "description": f"uses {SL_KEY}"}], system=f"env {GH_PAT_2}")

    assert result == "count"
    sent = proxy_server.sent[0]
    dumped = json.dumps({k: sent[k] for k in ("messages", "contents", "tools", "system")})
    for secret in (GH_PAT, GOOGLE, SL_KEY, GH_PAT_2):
        assert secret not in dumped
    assert sent["deployment"] == {"litellm_params": {"api_key": "provider-key"}}
    assert mw.pending_calls() == 0


async def test_provider_token_count_masking_is_installed_once(mw, mod):
    proxy_server = _proxy_server_with_counter()
    mod.install_token_count_masking(mw, proxy_server)
    mod.install_token_count_masking(mw, proxy_server)

    await proxy_server._try_provider_token_count(messages=[{"role": "user", "content": GH_PAT}])

    assert len(proxy_server.sent) == 1


async def test_provider_token_count_falls_back_to_local_when_masking_fails(mw, mod, monkeypatch):
    proxy_server = _proxy_server_with_counter()
    mod.install_token_count_masking(mw, proxy_server)

    def broken(*_):
        raise RuntimeError("bug")

    monkeypatch.setattr(mod, "_map_strings", broken)

    result = await proxy_server._try_provider_token_count(messages=[{"role": "user", "content": GH_PAT}])

    assert result is None
    assert proxy_server.sent == []


async def test_provider_token_count_with_positional_args_counts_locally(mw, mod):
    proxy_server = _proxy_server_with_counter()
    mod.install_token_count_masking(mw, proxy_server)

    assert await proxy_server._try_provider_token_count(None, "anthropic") is None
    assert proxy_server.sent == []


async def test_google_stream_flushes_into_candidate_with_null_content(mw):
    data = await mw.async_pre_call_hook(None, None, _gemini_request(), "agenerate_content_stream")
    fake = _gemini_fake(data)
    done = "data: " + json.dumps({"candidates": [{"index": 0, "content": None, "finishReason": "STOP"}]}) + "\n\n"

    out = await _collect(mw, [_gemini_sse("key " + fake[:10]).encode(), done.encode()], data)

    events, text, _ = _gemini_parse(out)
    assert text == "key " + fake[:10]
    assert events[-1]["candidates"][0]["finishReason"] == "STOP"


def test_token_count_masking_warns_when_litellm_moved_it(mw, mod, fake_litellm):
    mod.install_token_count_masking(mw, types.ModuleType("litellm.proxy.proxy_server"))

    assert any("token count" in w[0][0] for w in fake_litellm.verbose_proxy_logger.warnings)


@pytest.mark.parametrize("request_data", [None, {}, [], "x", {"litellm_call_id": ["unhashable"]}])
def test_wants_stream_never_raises(mw, request_data):
    assert mw.wants_stream(request_data) is False
