---
name: block-raw-container-run
enabled: true
event: bash
pattern: (^|\s|&&|\|\||;)(docker|podman)\s+run(\s|$)
action: block
---

🚫 **Use `agent-run` instead of raw `docker run`/`podman run`**

The `agent-run` wrapper enforces sandboxing defaults:

- `--userns=auto --read-only --cap-drop=ALL --security-opt no-new-privileges`
- `--network=bridge`
- Rejects `--privileged`, host namespaces, docker socket binds

Override the network via env: `AGENT_RUN_NET`.
