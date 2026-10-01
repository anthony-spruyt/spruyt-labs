"""Shares the fake-to-real map across replicas through Valkey, encrypted, so any pod can restore an echoed fake."""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import os
import time
from collections import OrderedDict
from typing import Any, Callable, Optional

from ..pipeline import MiddlewarePipeline


_log_warning = MiddlewarePipeline._log_warning
_KEY_PREFIX = "litellm:secret-masking:v1:"
_FORMAT = b"\x01"
_NONCE_LEN = 12


class SharedFakes:
    def __init__(
        self,
        salt: bytes,
        client_factory: Callable[[], Any],
        ttl_seconds: int = 3600,
        timeout: float = 0.5,
        write_timeout: float = 2.0,
        backoff_seconds: float = 15.0,
        cache_size: int = 10000,
    ) -> None:
        # Imported here so a missing library costs only sharing, not masking itself.
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
        from cryptography.hazmat.primitives.kdf.hkdf import HKDF

        keys = HKDF(algorithm=hashes.SHA256(), length=64, salt=None,
                    info=b"litellm-secret-masking-shared-v1").derive(salt)
        self._aead = AESGCM(keys[:32])
        self._mac_key = keys[32:]
        self._factory = client_factory
        self._client: Any = None
        self._ttl = int(ttl_seconds)
        self._timeout = timeout
        self._write_timeout = write_timeout
        self._backoff = backoff_seconds
        self._down_until = 0.0
        self._cache_size = cache_size
        self._pending: dict[str, dict[str, tuple[str, str]]] = {}
        self._flushing: Optional[asyncio.Task] = None
        self._inflight: dict[str, asyncio.Task] = {}
        self._written: OrderedDict[tuple[str, str], float] = OrderedDict()
        self._opened: OrderedDict[tuple[str, bytes, bytes], tuple[str, str]] = OrderedDict()

    def put(self, scope: Optional[str], fakes: dict[str, str]) -> None:
        """Queues fakes for a background write; never touches Valkey on the caller's path."""
        if scope is None or not fakes or self._down():
            return
        now = time.monotonic()
        sid = self._scope_id(scope)
        for fake, real in fakes.items():
            field = self._field(sid, fake)
            seen = self._written.get((sid, field))
            if seen is None or now - seen >= self._ttl / 2:
                self._pending.setdefault(sid, {})[field] = (fake, real)
        if not self._pending or self._flushing is not None:
            return
        try:
            self._flushing = asyncio.get_running_loop().create_task(self._flush())
        except RuntimeError:
            self._pending.clear()

    def fetch(self, scope: Optional[str]) -> Optional[asyncio.Task]:
        """Starts reading a scope's shared fakes in the background; concurrent callers share one read."""
        if scope is None or self._down():
            return None
        sid = self._scope_id(scope)
        task = self._inflight.get(sid)
        if task is None:
            try:
                task = asyncio.get_running_loop().create_task(self._fetch(sid))
            except RuntimeError:
                return None
            self._inflight[sid] = task
            task.add_done_callback(lambda _: self._inflight.pop(sid, None))
        return task

    async def result(self, task: asyncio.Task) -> dict[str, str]:
        try:
            # Shielded: other calls may be waiting on the same read.
            return await asyncio.shield(task)
        except Exception:  # noqa: BLE001 - sharing is best effort
            return {}

    async def drain(self) -> None:
        while self._flushing is not None:
            await self._flushing

    def _down(self) -> bool:
        return time.monotonic() < self._down_until

    def _fail(self, exc: BaseException) -> None:
        if not self._down():
            _log_warning("secret masking shared map unavailable, using local only: %s", type(exc).__name__)
        self._down_until = time.monotonic() + self._backoff

    def _connection(self) -> Any:
        if self._client is None:
            self._client = self._factory()
        return self._client

    async def _flush(self) -> None:
        try:
            while self._pending and not self._down():
                sid, entries = self._pending.popitem()
                key = self._key(sid)
                args: list[Any] = []
                for field, (fake, real) in entries.items():
                    args += [field, self._seal(key, field, fake, real)]
                try:
                    async with asyncio.timeout(self._write_timeout):
                        await self._connection().execute_command(
                            "HSETEX", key, "EX", self._ttl, "FIELDS", len(entries), *args)
                except Exception as exc:  # noqa: BLE001 - Valkey down must never fail a request
                    self._fail(exc)
                    break
                now = time.monotonic()
                for field in entries:
                    self._written[(sid, field)] = now
                    self._written.move_to_end((sid, field))
                while len(self._written) > self._cache_size:
                    self._written.popitem(last=False)
            self._pending.clear()
        finally:
            self._flushing = None

    async def _fetch(self, sid: str) -> dict[str, str]:
        key = self._key(sid)
        try:
            async with asyncio.timeout(self._timeout):
                raw = await self._connection().hgetall(key)
        except Exception as exc:  # noqa: BLE001 - Valkey down must never fail a request
            self._fail(exc)
            return {}
        out = {}
        for field, value in raw.items():
            pair = self._open(key, field, value)
            if pair is not None:
                out[pair[0]] = pair[1]
        return out

    def _seal(self, key: str, field: str, fake: str, real: str) -> bytes:
        nonce = os.urandom(_NONCE_LEN)
        plain = json.dumps([fake, real]).encode()
        return _FORMAT + nonce + self._aead.encrypt(nonce, plain, _aad(key, field.encode()))

    def _open(self, key: str, field: Any, value: Any) -> Optional[tuple[str, str]]:
        if not isinstance(field, bytes) or not isinstance(value, bytes) or value[:1] != _FORMAT:
            return None
        cache_key = (key, field, value)
        pair = self._opened.get(cache_key)
        if pair is not None:
            self._opened.move_to_end(cache_key)
            return pair
        nonce, sealed = value[1:1 + _NONCE_LEN], value[1 + _NONCE_LEN:]
        try:
            fake, real = json.loads(self._aead.decrypt(nonce, sealed, _aad(key, field)))
        except Exception:  # noqa: BLE001 - entries from another salt or tampered with are skipped
            return None
        if not isinstance(fake, str) or not isinstance(real, str):
            return None
        self._opened[cache_key] = (fake, real)
        while len(self._opened) > self._cache_size:
            self._opened.popitem(last=False)
        return fake, real

    def _scope_id(self, scope: str) -> str:
        return hmac.new(self._mac_key, b"scope\0" + scope.encode(), hashlib.sha256).hexdigest()[:32]

    def _field(self, sid: str, fake: str) -> str:
        msg = f"fake\0{sid}\0".encode() + fake.encode("utf-8", "surrogatepass")
        return hmac.new(self._mac_key, msg, hashlib.sha256).hexdigest()[:32]

    @staticmethod
    def _key(sid: str) -> str:
        return _KEY_PREFIX + sid


def _aad(key: str, field: bytes) -> bytes:
    # Binds each entry to its slot, so a copied entry cannot restore under another key or fake.
    return key.encode() + b"\0" + field


def shared_from_env() -> Optional[SharedFakes]:
    salt = os.environ.get("LITELLM_SALT_KEY")
    host = os.environ.get("REDIS_HOST")
    if not salt or not host:
        return None

    def client() -> Any:
        from redis.asyncio import Redis

        return Redis(
            host=host,
            port=int(os.environ.get("REDIS_PORT") or 6379),
            username=os.environ.get("REDIS_USERNAME") or None,
            password=os.environ.get("REDIS_PASSWORD") or None,
            socket_timeout=2,
            socket_connect_timeout=0.5,
        )

    try:
        return SharedFakes(salt.encode(), client)
    except Exception as exc:  # noqa: BLE001 - masking still works pod-local
        _log_warning("secret masking shared map disabled: %s", type(exc).__name__)
        return None
