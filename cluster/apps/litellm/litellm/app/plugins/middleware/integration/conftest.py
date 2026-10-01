"""Boots the pinned LiteLLM image with the middleware mounted exactly as the pod mounts it."""

from __future__ import annotations

import os
import shlex
import socket
import subprocess
import sys
import time
import uuid
from pathlib import Path

import httpx
import pytest
import yaml

sys.path.insert(0, str(Path(__file__).parent))
import pod_layout  # noqa: E402

MASTER_KEY = "it-master-key"
MODEL = "claude-it"
STARTUP_TIMEOUT_S = 240


def _runner() -> list[str]:
    # agent-run on Coder workspaces; it already passes --rm.
    return shlex.split(os.environ.get("LITELLM_IT_RUNNER", "docker run --rm"))


def _cli() -> str:
    # exec and rm; must share the runner's container store.
    return os.environ.get("LITELLM_IT_CLI", "docker")


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _config(callbacks: tuple[str, ...]) -> str:
    return yaml.safe_dump({
        "model_list": [{
            "model_name": MODEL,
            "litellm_params": {"model": f"anthropic/{MODEL}", "api_base": "http://127.0.0.1:8099", "api_key": "it"},
        }],
        "litellm_settings": {"callbacks": list(callbacks)},
        "general_settings": {"master_key": MASTER_KEY},
    })


@pytest.fixture(scope="session")
def layout() -> pod_layout.PodLayout:
    return pod_layout.load()


@pytest.fixture(scope="session")
def proxy(layout, tmp_path_factory):
    work = tmp_path_factory.mktemp("litellm-it")
    callbacks_dir = work / "custom_callbacks"
    callbacks_dir.mkdir()
    pod_layout.stage(layout, callbacks_dir)
    (work / "config.yaml").write_text(_config(layout.callbacks))
    (work / "fake_upstream.py").write_bytes((Path(__file__).parent / "fake_upstream.py").read_bytes())
    for path in [work, *work.rglob("*")]:
        path.chmod(0o755 if path.is_dir() else 0o644)

    name = f"litellm-it-{uuid.uuid4().hex[:8]}"
    port = _free_port()
    log_path = work / "proxy.log"
    # Foreground, not -d: --rm deletes a crashed container and its logs, so capture output ourselves.
    with log_path.open("w") as log:
        proc = subprocess.Popen([
            *_runner(), "--name", name,
            "-p", f"127.0.0.1:{port}:4000",
            "-e", f"PYTHONPATH={layout.pythonpath}",
            "-v", f"{callbacks_dir}:{pod_layout.CALLBACKS_ROOT}:ro",
            "-v", f"{work / 'config.yaml'}:/app/config.yaml:ro",
            "-v", f"{work / 'fake_upstream.py'}:/it/fake_upstream.py:ro",
            "--entrypoint", "sh",
            layout.image,
            "-c", "python /it/fake_upstream.py & exec litellm --config /app/config.yaml --port 4000",
        ], stdout=log, stderr=subprocess.STDOUT)

    proxy = Proxy(f"http://127.0.0.1:{port}", name, log_path)
    try:
        _wait_ready(proxy, proc)
        yield proxy
    finally:
        if os.environ.get("LITELLM_IT_SHOW_LOGS"):
            print(proxy.logs())
        subprocess.run([_cli(), "rm", "-f", name], capture_output=True)
        try:
            proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            proc.kill()


def _wait_ready(proxy: "Proxy", proc: subprocess.Popen) -> None:
    deadline = time.monotonic() + STARTUP_TIMEOUT_S
    while time.monotonic() < deadline:
        try:
            if httpx.get(f"{proxy.base}/health/readiness", timeout=2).status_code == 200:
                return
        except httpx.HTTPError:
            pass
        if proc.poll() is not None:
            pytest.fail(f"LiteLLM container exited during startup:\n{proxy.logs()}")
        time.sleep(2)
    pytest.fail(f"LiteLLM not ready after {STARTUP_TIMEOUT_S}s:\n{proxy.logs()}")


class Proxy:
    def __init__(self, base: str, name: str, log_path: Path) -> None:
        self.base = base
        self.name = name
        self.log_path = log_path
        self.client = httpx.Client(base_url=base, timeout=60,
                                   headers={"authorization": f"Bearer {MASTER_KEY}"})

    def logs(self) -> str:
        return self.log_path.read_text()

    def python(self, code: str) -> str:
        """Runs code in the proxy container, with its PYTHONPATH and LiteLLM install."""
        out = subprocess.run([_cli(), "exec", self.name, "python", "-c", code], capture_output=True, text=True)
        assert out.returncode == 0, out.stderr
        return out.stdout

    def upstream_received(self) -> list[dict]:
        # The fake upstream only listens inside the container.
        return yaml.safe_load(self.python(
            "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8099/_received').read().decode())"))
