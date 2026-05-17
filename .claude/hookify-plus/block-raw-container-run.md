---
name: block-raw-container-run
enabled: true
event: bash
pattern: (^|\s|&&|\|\||;)(docker|podman)\s+run(\s|$)
action: block
---

🚫 **Use `agent-run` instead of raw `docker run`/`podman run`**

The `agent-run` wrapper enforces rootless sandboxing defaults:

- `--userns=auto --read-only --cap-drop=ALL`
- `--pids-limit=512 --memory=2g --cpus=2`
- `--network=slirp4netns:allow_host_loopback=false`
- Rejects `--privileged`, host namespaces, docker socket binds

Override via env: `AGENT_RUN_NET|MEM|PIDS|CPUS`.
