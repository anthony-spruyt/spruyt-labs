# Fix gh CLI in Claude Agent Pods — Writable Config Directory

**Issue:** [#1048](https://github.com/anthony-spruyt/spruyt-labs/issues/1048) **Date:** 2026-04-26 **Status:** Draft

## Problem

The `gh` CLI is broken in Claude agent pods spawned by n8n. The Kyverno mutation policy `inject-claude-agent-config` mounts the `github-bot-credentials` secret directly at `/etc/gh` and sets `GH_CONFIG_DIR=/etc/gh`. Kubernetes secret volumes are read-only at the kernel level, but `gh` needs to write state files (`config.yml`, etc.) to its config directory.

## Constraints

- **Token rotation**: GitHub bot tokens rotate every 30 minutes, expire after 1 hour. Must read from live secret volume — copies go stale.
- **Secret volumes are kernel read-only**: Cannot make the secret mount writable.
- **`GH_TOKEN` env var not viable**: Would require pod restart on rotation. File-based auth via `hosts.yml` is the only option.
- **Cannot override container command/entrypoint**: Breaks n8n Claude Code plugin, even with custom images.
- **All agent pods have `managed-by: n8n-claude-code` label**: No blast radius concern from the selector.

## Rejected Approaches

| Approach                     | Why Rejected                                                                                 |
| ---------------------------- | -------------------------------------------------------------------------------------------- |
| **postStart lifecycle hook** | Race condition — runs concurrently with entrypoint. `gh` may execute before symlink created. |
| **Command wrapper override** | Breaks n8n plugin. Confirmed by prior testing.                                               |
| **`GH_TOKEN` env var**       | Stale after rotation. Requires pod restart.                                                  |
| **subPath secret mount**     | kubelet does not update subPath mounts when secret rotates. Breaks token rotation.           |
| **Copy token at init time**  | Same staleness problem as `GH_TOKEN`.                                                        |

## Solution: emptyDir + Symlink Init Container

Use a writable `emptyDir` as `GH_CONFIG_DIR` with a symlink to the read-only secret mount for `hosts.yml`. Token rotation propagates through the symlink because kubelet updates the secret volume atomically (non-subPath mounts).

### Volume Changes

| Volume                          | Before               | After                            |
| ------------------------------- | -------------------- | -------------------------------- |
| `github-gh-config` (secret)     | Mounted at `/etc/gh` | Mounted at `/etc/gh-secret`      |
| `gh-config-writable` (emptyDir) | —                    | New. Mounted at `/tmp/gh-config` |

### Env Var Change

| Env Var         | Before    | After            |
| --------------- | --------- | ---------------- |
| `GH_CONFIG_DIR` | `/etc/gh` | `/tmp/gh-config` |

### Init Container

Added to `inject-shared-config` rule in the Kyverno policy:

```yaml
initContainers:
  - name: gh-config-init
    image: "busybox:1.37.0@sha256:1487d0af5f52b4ba31c7e465126ee2123fe3f2305d638e7827681e7cf6c83d5e"
    command: ["sh", "-c"]
    args:
      - ln -s /etc/gh-secret/hosts.yml /tmp/gh-config/hosts.yml
    volumeMounts:
      - name: github-gh-config
        mountPath: /etc/gh-secret
        readOnly: true
      - name: gh-config-writable
        mountPath: /tmp/gh-config
```

### Runtime Behavior

1. kubelet mounts `github-bot-credentials` secret at `/etc/gh-secret/hosts.yml` (read-only)
1. `gh-config-init` creates symlink: `/tmp/gh-config/hosts.yml` → `/etc/gh-secret/hosts.yml`
1. Main container starts with `GH_CONFIG_DIR=/tmp/gh-config`
1. `gh` reads `hosts.yml` via symlink → follows to live secret → always has current token
1. `gh` writes `config.yml` and state files to writable emptyDir → no read-only errors
1. When token rotates, kubelet atomically updates `/etc/gh-secret/hosts.yml` → symlink resolves to new content

### Main Container Mount Changes

The main container(s) `(name): "?*"` volumeMounts update:

| Mount                | Before               | After                                       |
| -------------------- | -------------------- | ------------------------------------------- |
| `github-gh-config`   | `mountPath: /etc/gh` | `mountPath: /etc/gh-secret`                 |
| `gh-config-writable` | —                    | `mountPath: /tmp/gh-config` (new, writable) |

Both the init container and main container mount `gh-config-writable` at `/tmp/gh-config` — init container writes the symlink, main container reads/writes through it.

### Init Container Ordering

Kyverno `patchStrategicMerge` appends init containers. `gh-config-init` has no dependency on `git-clone` (conditional on `CLONE_URL`) and vice versa. Both complete before main container starts.

## File Changed

| File                                                                | Change                                                                                                                              |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml` | Modify `inject-shared-config` rule: add emptyDir volume, add init container, move secret mount path, update `GH_CONFIG_DIR` env var |

## Testing

1. Spawn a test agent pod in `claude-agents-read` namespace
1. Verify init container `gh-config-init` completes successfully
1. Verify symlink exists: `ls -la /tmp/gh-config/hosts.yml` → points to `/etc/gh-secret/hosts.yml`
1. Verify `gh auth status` succeeds
1. Verify `gh` can write state files (no read-only errors)
1. Wait for token rotation (~30min) and verify `gh auth status` still works with new token
