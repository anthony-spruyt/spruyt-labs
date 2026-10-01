import asyncio
import importlib
import json
import os
import sys
import types

import pytest


_HERE = os.path.dirname(__file__)
_PLUGINS_DIR = os.path.dirname(os.path.dirname(os.path.dirname(_HERE)))
if _PLUGINS_DIR not in sys.path:
    sys.path.insert(0, _PLUGINS_DIR)


# Built by concatenation so secret scanners don't flag the fixtures.
GH_PAT = "gh" + "p_" + "aB3dE5gH7jK9mN1pQ3sT5vW7yZ9bC1dE3fG5"
GH_PAT_2 = "gh" + "p_" + "Zy8xW6vU4tS2rQ0pO8nM6lK4jI2hG0fE8dC6"
SCOPE = "hashed-virtual-key"


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
    custom_logger = types.ModuleType("litellm.integrations.custom_logger")
    custom_logger.CustomLogger = type("CustomLogger", (), {})
    monkeypatch.setitem(sys.modules, "litellm", litellm)
    monkeypatch.setitem(sys.modules, "litellm._logging", logging)
    monkeypatch.setitem(sys.modules, "litellm.integrations", types.ModuleType("litellm.integrations"))
    monkeypatch.setitem(sys.modules, "litellm.integrations.custom_logger", custom_logger)
    return logging


@pytest.fixture
def sf():
    for name in (
        "middleware.secret_masking.shared_fakes",
        "middleware.secret_masking.secret_masking",
        "middleware.pipeline",
    ):
        sys.modules.pop(name, None)
    return importlib.import_module("middleware.secret_masking.shared_fakes")


@pytest.fixture
def sm(sf):
    return importlib.import_module("middleware.secret_masking.secret_masking")


class FakeValkey:
    def __init__(self):
        self.now = 0.0
        self.data: dict[str, dict[bytes, tuple[bytes, float]]] = {}
        self.calls: list[str] = []
        self.fail: Exception | None = None
        self.delay = 0.0

    async def _enter(self, name):
        self.calls.append(name)
        if self.delay:
            await asyncio.sleep(self.delay)
        if self.fail is not None:
            raise self.fail

    async def execute_command(self, *args):
        await self._enter(args[0])
        assert args[0] == "HSETEX"
        key, ex, ttl, fields, count, *pairs = args[1:]
        assert (ex, fields) == ("EX", "FIELDS")
        assert count == len(pairs) // 2
        entries = self.data.setdefault(key, {})
        for field, value in zip(pairs[::2], pairs[1::2]):
            entries[field.encode()] = (value, self.now + ttl)
        return 1

    async def hgetall(self, key):
        await self._enter("HGETALL")
        return {f: v for f, (v, expires) in self.data.get(key, {}).items() if expires > self.now}

    def stored(self):
        return [(key, field, value) for key, entries in self.data.items() for field, (value, _) in entries.items()]


@pytest.fixture
def valkey():
    return FakeValkey()


def _store(sf, valkey, **kwargs):
    return sf.SharedFakes(b"salt", lambda: valkey, **kwargs)


async def _fetch(store, scope=SCOPE):
    task = store.fetch(scope)
    return {} if task is None else await store.result(task)


async def test_round_trip(sf, valkey):
    store = _store(sf, valkey)
    store.put(SCOPE, {"fake-1": GH_PAT})
    await store.drain()

    assert await _fetch(_store(sf, valkey)) == {"fake-1": GH_PAT}


async def test_scopes_are_isolated(sf, valkey):
    store = _store(sf, valkey)
    store.put(SCOPE, {"fake-1": GH_PAT})
    await store.drain()

    assert await _fetch(store, "other-key") == {}
    assert await _fetch(store, None) == {}


async def test_put_does_not_touch_valkey_until_the_loop_runs(sf, valkey):
    store = _store(sf, valkey)
    store.put(SCOPE, {"fake-1": GH_PAT})
    store.put(SCOPE, {"fake-2": GH_PAT_2})

    assert valkey.calls == []
    await store.drain()
    assert valkey.calls == ["HSETEX"]


async def test_entries_expire(sf, valkey):
    store = _store(sf, valkey, ttl_seconds=60)
    store.put(SCOPE, {"fake-1": GH_PAT})
    await store.drain()

    valkey.now += 61
    assert await _fetch(store) == {}


async def test_encrypted_at_rest_and_keyed_by_hmac(sf, valkey):
    store = _store(sf, valkey)
    store.put(SCOPE, {"fake-value-1": GH_PAT})
    await store.drain()

    [(key, field, value)] = valkey.stored()
    for secret in (GH_PAT, "fake-value-1", SCOPE):
        assert secret not in key
        assert secret.encode() not in field
        assert secret.encode() not in value
    assert key.startswith("litellm:secret-masking:v1:")
    assert value[:1] == b"\x01"


async def test_tampered_or_foreign_entries_are_skipped(sf, valkey):
    store = _store(sf, valkey)
    store.put(SCOPE, {"fake-1": GH_PAT, "fake-2": GH_PAT_2})
    await store.drain()
    [key] = valkey.data
    fields = list(valkey.data[key])
    value, expires = valkey.data[key][fields[0]]
    valkey.data[key][fields[0]] = (value[:-1] + bytes([value[-1] ^ 1]), expires)

    assert len(await _fetch(store)) == 1
    assert await _fetch(sf.SharedFakes(b"other-salt", lambda: valkey)) == {}


async def test_moved_entry_fails_authentication(sf, valkey):
    store = _store(sf, valkey)
    store.put(SCOPE, {"fake-1": GH_PAT})
    await store.drain()
    [(key, field, value)] = valkey.stored()
    other_key = store._key(store._scope_id("other-key"))
    valkey.data[other_key] = {field: (value, float("inf"))}

    assert await _fetch(store, "other-key") == {}


async def test_rewrites_are_deduplicated_until_half_ttl(sf, valkey, monkeypatch):
    now = [1000.0]
    monkeypatch.setattr(sf.time, "monotonic", lambda: now[0])
    store = _store(sf, valkey, ttl_seconds=60)
    store.put(SCOPE, {"fake-1": GH_PAT})
    await store.drain()
    store.put(SCOPE, {"fake-1": GH_PAT})
    await store.drain()
    assert valkey.calls == ["HSETEX"]

    now[0] += 31
    store.put(SCOPE, {"fake-1": GH_PAT})
    await store.drain()
    assert valkey.calls == ["HSETEX", "HSETEX"]


async def test_concurrent_fetches_for_a_scope_share_one_read(sf, valkey):
    store = _store(sf, valkey)

    assert store.fetch(SCOPE) is store.fetch(SCOPE)
    await asyncio.sleep(0)
    assert valkey.calls == ["HGETALL"]


async def test_valkey_down_falls_back_and_backs_off(sf, valkey, fake_litellm, monkeypatch):
    now = [1000.0]
    monkeypatch.setattr(sf.time, "monotonic", lambda: now[0])
    valkey.fail = ConnectionError(f"cannot reach {GH_PAT}")
    store = _store(sf, valkey, backoff_seconds=30)

    assert await _fetch(store) == {}
    store.put(SCOPE, {"fake-1": GH_PAT})
    await store.drain()

    assert valkey.calls == ["HGETALL"]
    warnings = fake_litellm.verbose_proxy_logger.warnings
    assert len(warnings) == 1
    assert "ConnectionError" in warnings[0][0]
    assert GH_PAT not in repr(warnings)

    valkey.fail = None
    now[0] += 31
    store.put(SCOPE, {"fake-1": GH_PAT})
    await store.drain()
    assert await _fetch(store) == {"fake-1": GH_PAT}


async def test_failed_write_is_retried_on_next_put(sf, valkey, monkeypatch):
    now = [1000.0]
    monkeypatch.setattr(sf.time, "monotonic", lambda: now[0])
    store = _store(sf, valkey, backoff_seconds=30)
    valkey.fail = ConnectionError()
    store.put(SCOPE, {"fake-1": GH_PAT})
    await store.drain()

    valkey.fail = None
    now[0] += 31
    store.put(SCOPE, {"fake-1": GH_PAT})
    await store.drain()
    assert await _fetch(store) == {"fake-1": GH_PAT}


async def test_slow_valkey_does_not_block_result(sf, valkey):
    valkey.delay = 5
    store = _store(sf, valkey, timeout=0.01)

    task = store.fetch(SCOPE)
    assert await asyncio.wait_for(store.result(task), 1) == {}
    task.cancel()


async def test_client_factory_failure_disables_sharing(sf, fake_litellm):
    def broken():
        raise RuntimeError("no redis")

    store = sf.SharedFakes(b"salt", broken)
    assert await _fetch(store) == {}
    store.put(SCOPE, {"fake-1": GH_PAT})
    await store.drain()
    assert len(fake_litellm.verbose_proxy_logger.warnings) == 1


def test_from_env_needs_salt_and_host(sf, monkeypatch):
    monkeypatch.delenv("LITELLM_SALT_KEY", raising=False)
    monkeypatch.setenv("REDIS_HOST", "valkey")
    assert sf.shared_from_env() is None

    monkeypatch.setenv("LITELLM_SALT_KEY", "salt")
    monkeypatch.delenv("REDIS_HOST", raising=False)
    assert sf.shared_from_env() is None

    monkeypatch.setenv("REDIS_HOST", "valkey")
    assert isinstance(sf.shared_from_env(), sf.SharedFakes)


# --- middleware integration: two replicas sharing one Valkey ---


def _user(scope=SCOPE):
    return types.SimpleNamespace(api_key=scope)


def _request(text, call_id):
    return {"litellm_call_id": call_id,
            "messages": [{"role": "user", "content": [{"type": "text", "text": text}]}]}


def _pod(sm, sf, valkey):
    return sm.SecretMaskingMiddleware(key=b"k", shared=_store(sf, valkey))


async def _turn_one(pod, secret=GH_PAT):
    data = await pod.async_pre_call_hook(_user(), None, _request(secret, "turn-1"), "anthropic_messages")
    fake = data["messages"][0]["content"][0]["text"]
    await pod.async_post_call_success_hook(data=data, user_api_key_dict=_user(), response={"t": "ok"})
    await pod._shared.drain()
    return fake


async def test_fake_from_other_replica_is_restored(sm, sf, valkey):
    fake = await _turn_one(_pod(sm, sf, valkey))
    pod_b = _pod(sm, sf, valkey)

    data = await pod_b.async_pre_call_hook(_user(), None, _request("continue", "turn-2"), "anthropic_messages")
    out = await pod_b.async_post_call_success_hook(
        data=data, user_api_key_dict=_user(), response={"content": [{"type": "text", "text": f"use {fake}"}]})

    assert out["content"][0]["text"] == f"use {GH_PAT}"
    assert pod_b.pending_calls() == 0


async def test_fake_from_other_replica_is_restored_in_stream(sm, sf, valkey):
    fake = await _turn_one(_pod(sm, sf, valkey))
    pod_b = _pod(sm, sf, valkey)
    data = await pod_b.async_pre_call_hook(_user(), None, _request("continue", "turn-2"), "anthropic_messages")
    assert pod_b.wants_stream(data)

    events = [{"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": p}}
              for p in (f"use {fake[:10]}", fake[10:], " ok")]
    events.append({"type": "message_stop"})

    async def upstream():
        for event in events:
            yield event

    out = [c async for c in pod_b.async_post_call_streaming_iterator_hook(
        response=upstream(), request_data=data, user_api_key_dict=_user())]

    text = "".join(e["delta"]["text"] for e in out if e["type"] == "content_block_delta")
    assert text == f"use {GH_PAT} ok"
    assert pod_b.pending_calls() == 0


async def test_other_virtual_key_cannot_restore(sm, sf, valkey):
    fake = await _turn_one(_pod(sm, sf, valkey))
    pod_b = _pod(sm, sf, valkey)

    data = await pod_b.async_pre_call_hook(
        _user("another-key"), None, _request("continue", "turn-2"), "anthropic_messages")
    out = await pod_b.async_post_call_success_hook(
        data=data, user_api_key_dict=_user("another-key"),
        response={"content": [{"type": "text", "text": fake}]})

    assert out["content"][0]["text"] == fake


async def test_clean_stream_passes_through_untouched(sm, sf, valkey):
    pod = _pod(sm, sf, valkey)
    data = await pod.async_pre_call_hook(_user(), None, _request("hi", "turn-1"), "anthropic_messages")
    chunks = [b"data: {\"type\": \"ping\"}\n\n"]

    async def upstream():
        for chunk in chunks:
            yield chunk

    out = [c async for c in pod.async_post_call_streaming_iterator_hook(
        response=upstream(), request_data=data, user_api_key_dict=_user())]

    assert out == chunks
    assert pod.pending_calls() == 0


async def test_pre_call_does_not_wait_for_valkey(sm, sf, valkey):
    valkey.delay = 5
    pod = _pod(sm, sf, valkey)

    await asyncio.wait_for(
        pod.async_pre_call_hook(_user(), None, _request(GH_PAT, "turn-1"), "anthropic_messages"), 0.5)


async def test_valkey_down_keeps_local_restore(sm, sf, valkey):
    valkey.fail = ConnectionError()
    pod = _pod(sm, sf, valkey)
    fake = await _turn_one(pod)

    data = await pod.async_pre_call_hook(_user(), None, _request("continue", "turn-2"), "anthropic_messages")
    out = await pod.async_post_call_success_hook(
        data=data, user_api_key_dict=_user(), response={"content": [{"type": "text", "text": fake}]})

    assert out["content"][0]["text"] == GH_PAT
