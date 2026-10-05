import json
import secrets
import string

import pytest

from conftest import MASTER_KEY, MCP_SERVER, MODEL


def _github_token() -> str:
    alphabet = string.ascii_letters + string.digits
    return "ghp_" + "".join(secrets.choice(alphabet) for _ in range(36))


def _ask(text: str, stream: bool = False) -> dict:
    return {"model": MODEL, "max_tokens": 64, "stream": stream,
            "messages": [{"role": "user", "content": f"my token is {text} ok"}]}


def _sent_upstream(proxy, token: str) -> str:
    messages = [r for r in proxy.upstream_received() if r["path"].startswith("/v1/messages")]
    sent = json.dumps(messages[-1]["body"])
    assert token not in sent, "real secret reached the model"
    return sent


def test_proxy_starts_without_middleware_errors(proxy):
    logs = proxy.logs()
    assert "failed to load" not in logs
    assert "Traceback" not in logs


def test_messages_masks_upstream_and_restores_reply(proxy):
    token = _github_token()
    resp = proxy.client.post("/v1/messages", json=_ask(token))
    assert resp.status_code == 200, resp.text

    sent = _sent_upstream(proxy, token)
    assert "ghp_" in sent, "fake should keep the recognisable prefix"
    assert resp.json()["content"][0]["text"] == f"echo: my token is {token} ok"


def test_streamed_messages_restore_fake_split_across_chunks(proxy):
    token = _github_token()
    with proxy.client.stream("POST", "/v1/messages", json=_ask(token, stream=True)) as resp:
        assert resp.status_code == 200
        frames = [json.loads(line[5:]) for line in resp.iter_lines() if line.startswith("data:")]

    _sent_upstream(proxy, token)
    text = "".join(f["delta"]["text"] for f in frames
                   if f.get("type") == "content_block_delta" and f["delta"].get("type") == "text_delta")
    assert text == f"echo: my token is {token} ok"


def test_chat_completions_masks_upstream_and_restores_reply(proxy):
    token = _github_token()
    resp = proxy.client.post("/v1/chat/completions", json={
        "model": MODEL, "max_tokens": 64,
        "messages": [{"role": "user", "content": f"my token is {token} ok"}]})
    assert resp.status_code == 200, resp.text

    _sent_upstream(proxy, token)
    assert resp.json()["choices"][0]["message"]["content"] == f"echo: my token is {token} ok"


_COUNT_TOKENS = """
import asyncio, json, sys
import litellm.proxy.proxy_server as ps
import custom_callbacks.middleware.pipeline_plugin

seen = {}

class Counter:
    def should_use_token_counting_api(self, custom_llm_provider=None):
        return True

    async def count_tokens(self, **kwargs):
        seen.update(kwargs)

asyncio.run(ps._try_provider_token_count(
    provider_counter=Counter(), custom_llm_provider="anthropic", model_to_use="m", contents=None,
    deployment=None, request_model="m", messages=[{"role": "user", "content": sys.argv[1]}],
    system=sys.argv[1], tools=None))
print(json.dumps(seen))
"""


def test_proxy_wraps_provider_token_count(proxy):
    assert "has no _try_provider_token_count" not in proxy.logs()


def test_provider_token_count_is_masked(proxy):
    token = _github_token()
    sent = proxy.python(_COUNT_TOKENS.replace("sys.argv[1]", repr(f"my token is {token}")))
    assert '"messages"' in sent and '"system"' in sent
    assert token not in sent


@pytest.mark.parametrize("stream", [False, True])
def test_ratelimit_headers_reach_client(proxy, stream):
    with proxy.client.stream("POST", "/v1/messages", json=_ask("hello", stream=stream)) as resp:
        resp.read()
    assert resp.headers.get("anthropic-ratelimit-unified-status") == "allowed"
    assert resp.headers.get("anthropic-ratelimit-unified-5h-utilization") == "0.42"


@pytest.mark.parametrize("path", ["/v1/chat/completions", "/v1/messages"])
def test_error_body_carries_call_id(proxy, path):
    resp = proxy.client.post(path, json={
        "model": "no-such-model", "max_tokens": 64, "messages": [{"role": "user", "content": "hi"}]})

    assert resp.status_code >= 400, resp.text
    call_id = resp.headers.get("x-litellm-call-id")
    assert call_id, resp.headers
    assert resp.json()["error"].get("litellm_call_id") == call_id, resp.text


def test_mcp_tool_call_routes_on_a_cold_tool_mapping(proxy):
    proxy.start_fake_mcp()

    resp = proxy.client.post(
        "/mcp",
        headers={"x-litellm-api-key": f"Bearer {MASTER_KEY}", "accept": "application/json, text/event-stream"},
        json={"jsonrpc": "2.0", "id": 1, "method": "tools/call",
              "params": {"name": f"{MCP_SERVER}-echo", "arguments": {"text": "hi"}}},
    )

    assert resp.status_code == 200, resp.text
    assert "echo: hi" in resp.text, resp.text
