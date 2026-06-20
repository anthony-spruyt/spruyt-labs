"""Red-green TDD suite for HindsightMiddleware.

Covers recall injection (Anthropic str/blocks, OpenAI), bank resolution skip,
retain on success, and fail-open behavior on timeout.
"""

import copy

import httpx
import pytest

BANK_HEADER = "x-hindsight-bank"
MEMORY = "Cilium BGP uses CiliumBGPPeeringPolicy in this cluster."


def _mw(plugin):
    return plugin.hindsight_middleware


# 1 — recall injects into Anthropic string system prompt -------------------
async def test_recall_injects_into_anthropic_system(plugin, mock_httpx, make_anthropic, make_key):
    mock_httpx.recall_texts = [MEMORY]
    data = make_anthropic(system="You are a Kubernetes assistant.",
                          headers={BANK_HEADER: "my-repo"})
    out = await _mw(plugin).async_pre_call_hook(
        make_key(), None, data, "anthropic_messages")

    assert MEMORY in str(out["system"])
    assert "You are a Kubernetes assistant." in str(out["system"])
    assert len(mock_httpx.recall_calls) == 1
    assert mock_httpx.recall_calls[0]["url"].endswith(
        "/v1/default/banks/my-repo/memories/recall")


# 2 — Anthropic system as block list: memory appended LAST -----------------
async def test_anthropic_system_as_blocks_injection(plugin, mock_httpx, make_anthropic, make_key):
    mock_httpx.recall_texts = [MEMORY]
    blocks = [
        {"type": "text", "text": "cached system header"},
        {"type": "text", "text": "second cached block"},
    ]
    data = make_anthropic(system=copy.deepcopy(blocks),
                          headers={BANK_HEADER: "my-repo"})
    out = await _mw(plugin).async_pre_call_hook(
        make_key(), None, data, "anthropic_messages")

    assert isinstance(out["system"], list)
    # original blocks preserved as a cache-safe prefix
    assert out["system"][0] == blocks[0]
    assert out["system"][1] == blocks[1]
    # memory is the LAST block
    assert MEMORY in out["system"][-1]["text"]
    assert out["system"][-1]["type"] == "text"


# 3 — no bank → skip entirely, httpx never called --------------------------
async def test_no_bank_skips(plugin, mock_httpx, make_anthropic, make_key):
    data = make_anthropic(system="sys", headers={})
    before = copy.deepcopy(data)
    out = await _mw(plugin).async_pre_call_hook(
        make_key(), None, data, "anthropic_messages")

    assert out == before
    assert mock_httpx.calls == []


# 4 — retain POSTs one conversation item with async:true on success -------
# litellm nests proxy_server_request inside litellm_params for the success
# event (litellm_logging.py: get_litellm_params -> litellm_params dict), unlike
# the pre-call hook where it is top-level on `data`.
#
# The item's `content` MUST be a JSON-encoded conversation array
# (list of {role, content} dicts). Upstream chunk_text() (fact_extraction.py)
# only takes the whole-turn-preserving _chunk_conversation path when it can
# json.loads the content into a list of dicts; a bare turn string falls through
# to plain-text splitting at retain_chunk_size and fragments the memory.
async def test_retain_sends_conversation_array(plugin, mock_httpx, make_response):
    import json

    kwargs = {
        "litellm_call_id": "call-abc123",
        "litellm_params": {
            "proxy_server_request": {"headers": {BANK_HEADER: "my-repo"}},
        },
        "messages": [{"role": "user", "content": "How do I configure Cilium BGP?"}],
    }
    await _mw(plugin).async_log_success_event(
        kwargs, make_response(), 0.0, 1.0)

    assert len(mock_httpx.retain_calls) == 1
    body = mock_httpx.retain_calls[0]["json"]
    assert body["async"] is True
    # Exactly ONE item per exchange — the whole conversation, not split per role.
    assert isinstance(body["items"], list) and len(body["items"]) == 1
    item = body["items"][0]
    # content is a JSON string (Hindsight MemoryItem.content is str|null).
    assert isinstance(item["content"], str)
    conversation = json.loads(item["content"])
    assert isinstance(conversation, list)
    assert all(isinstance(t, dict) for t in conversation)
    roles = [t.get("role") for t in conversation]
    assert roles == ["user", "assistant"]
    assert all(isinstance(t.get("content"), str) and t["content"] for t in conversation)
    # context is str|null (a dict here yields HTTP 422); metadata is dict[str,str].
    assert "context" not in item or isinstance(item["context"], (str, type(None)))
    if "metadata" in item:
        assert all(isinstance(v, str) for v in item["metadata"].values())
    assert mock_httpx.retain_calls[0]["url"].endswith(
        "/v1/default/banks/my-repo/memories")


# 5 — retain skipped without bank, no raise --------------------------------
async def test_retain_skipped_without_bank(plugin, mock_httpx, make_response):
    kwargs = {
        "proxy_server_request": {"headers": {}},
        "messages": [{"role": "user", "content": "hello"}],
    }
    await _mw(plugin).async_log_success_event(
        kwargs, make_response(), 0.0, 1.0)

    assert mock_httpx.calls == []


# 6 — pre-call fails open on timeout (returns original data, no raise) ------
async def test_pre_call_fails_open_on_timeout(plugin, mock_httpx, make_anthropic, make_key):
    mock_httpx.raise_exc = httpx.TimeoutException("recall timed out")
    data = make_anthropic(system="sys", headers={BANK_HEADER: "my-repo"})
    before = copy.deepcopy(data)
    out = await _mw(plugin).async_pre_call_hook(
        make_key(), None, data, "anthropic_messages")

    assert out["system"] == before["system"]
    assert "<hindsight-memory>" not in str(out["system"])


# 7 — OpenAI completion with no system message → system message created -----
async def test_openai_system_message_injection(plugin, mock_httpx, make_openai, make_key):
    mock_httpx.recall_texts = [MEMORY]
    data = make_openai(headers={BANK_HEADER: "my-repo"})
    out = await _mw(plugin).async_pre_call_hook(
        make_key(), None, data, "completion")

    assert out["messages"][0]["role"] == "system"
    assert MEMORY in str(out["messages"][0]["content"])
    # original user message preserved
    assert any(m["role"] == "user" for m in out["messages"])


# bonus — bank resolved from virtual-key metadata when no header -----------
async def test_bank_from_key_metadata(plugin, mock_httpx, make_anthropic, make_key):
    mock_httpx.recall_texts = [MEMORY]
    data = make_anthropic(system="sys", headers={})
    key = make_key(metadata={"hindsight_bank": "key-bank"})
    out = await _mw(plugin).async_pre_call_hook(
        key, None, data, "anthropic_messages")

    assert mock_httpx.recall_calls[0]["url"].endswith(
        "/v1/default/banks/key-bank/memories/recall")
    assert MEMORY in str(out["system"])


async def test_responses_input_text_used_for_recall(plugin, mock_httpx, make_responses, make_key):
    mock_httpx.recall_texts = [MEMORY]
    data = make_responses(headers={BANK_HEADER: "my-repo"})

    out = await _mw(plugin).async_pre_call_hook(
        make_key(), None, data, "responses")

    assert mock_httpx.recall_calls[0]["json"]["query"] == "How do I configure Cilium BGP?"
    assert MEMORY in out["messages"][0]["content"]


async def test_retain_bank_from_team_metadata(plugin, mock_httpx, make_response):
    kwargs = {
        "litellm_params": {
            "metadata": {
                "team_metadata": {"hindsight_bank": "team-bank"},
            },
        },
        "messages": [{"role": "user", "content": "How do I configure Cilium BGP?"}],
    }

    await _mw(plugin).async_log_success_event(kwargs, make_response(), 0.0, 1.0)

    assert len(mock_httpx.retain_calls) == 1
    assert mock_httpx.retain_calls[0]["url"].endswith(
        "/v1/default/banks/team-bank/memories")
