# Fix gh CLI in Claude Agent Pods — Writable Config Directory

**Issue:** [#1048](https://github.com/anthony-spruyt/spruyt-labs/issues/1048) **Date:** 2026-04-26 **Status:** Complete

## Problem

The `gh` CLI is broken in Claude agent pods spawned by n8n. The Kyverno mutation policy `inject-claude-agent-config` mounts the `github-bot-credentials` secret directly at `/etc/gh` and sets `GH_CONFIG_DIR=/etc/gh`. Kubernetes secret volumes are read-only at the kernel level, but `gh` needs to write state files (`config.yml`, `hosts.yml` during migration) to its config directory.

## Constraints

- **Token rotation**: GitHub bot tokens rotate every 30 minutes, expire after 1 hour. Must stay fresh for persistent pods.
- **Secret volumes are kernel read-only**: Cannot make the secret mount writable.
- **`GH_TOKEN` env var not viable**: Would require pod restart on rotation. File-based auth via `hosts.yml` is the only option.
- **Cannot override container command/entrypoint**: Breaks n8n Claude Code plugin, even with custom images.
- **All agent pods have `managed-by: n8n-claude-code` label**: No blast radius concern from the selector.
- **Pod-level `runAsNonRoot: true`**: Init/sidecar containers must specify a non-root UID.
- **`gh` rewrites `hosts.yml` during config migration**: Symlinks don't work — writes follow through to read-only secret volume.

## Rejected Approaches

| Approach                     | Why Rejected                                                                                          |
| ---------------------------- | ----------------------------------------------------------------------------------------------------- |
| **postStart lifecycle hook** | Race condition — runs concurrently with entrypoint. `gh` may execute before config ready.             |
| **Command wrapper override** | Breaks n8n plugin. Confirmed by prior testing.                                                        |
| **`GH_TOKEN` env var**       | Stale after rotation. Requires pod restart.                                                           |
| **subPath secret mount**     | kubelet does not update subPath mounts when secret rotates. Breaks token rotation.                    |
| **Copy token at init time**  | Stale for persistent pods (>30min).                                                                   |
| **Symlink init container**   | `gh` rewrites `hosts.yml` during config migration — write follows symlink to read-only secret volume. |
| **Symlink native sidecar**   | Same symlink write-through problem as above.                                                          |

## Solution: Native Sidecar with Copy Loop

Use a native sidecar container (`restartPolicy: Always`) that copies `hosts.yml` from the read-only secret mount into a writable `emptyDir` every 30 seconds with `chmod 666` for cross-UID write access. `gh` gets a fully writable config directory, and the token stays fresh via periodic copy.

### Volume Changes

| Volume                          | Before               | After                            |
| ------------------------------- | -------------------- | -------------------------------- |
| `github-gh-config` (secret)     | Mounted at `/etc/gh` | Mounted at `/etc/gh-secret`      |
| `gh-config-writable` (emptyDir) | —                    | New. Mounted at `/tmp/gh-config` |

### Env Var Change

| Env Var         | Before    | After            |
| --------------- | --------- | ---------------- |
| `GH_CONFIG_DIR` | `/etc/gh` | `/tmp/gh-config` |

### Native Sidecar

Added to `inject-shared-config` rule as an init container with `restartPolicy: Always` (Kubernetes native sidecar pattern, requires k8s 1.28+):

```yaml
initContainers:
  - name: gh-config-sync
    image: "busybox:1.37.0@sha256:1487d0af5f52b4ba31c7e465126ee2123fe3f2305d638e7827681e7cf6c83d5e"
    restartPolicy: Always
    command: ["sh", "-c"]
    args:
      - |
        cp /etc/gh-secret/hosts.yml /tmp/gh-config/hosts.yml
        chmod 666 /tmp/gh-config/hosts.yml
        while true; do
          sleep 30
          cp /etc/gh-secret/hosts.yml /tmp/gh-config/hosts.yml
          chmod 666 /tmp/gh-config/hosts.yml
        done
    securityContext:
      runAsUser: 65534
      runAsGroup: 65534
      runAsNonRoot: true
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
    volumeMounts:
      - name: github-gh-config
        mountPath: /etc/gh-secret
        readOnly: true
      - name: gh-config-writable
        mountPath: /tmp/gh-config
```

### Runtime Behavior

1. kubelet mounts `github-bot-credentials` secret at `/etc/gh-secret/hosts.yml` (read-only)
1. `gh-config-sync` sidecar starts before main container, copies `hosts.yml` to emptyDir with world-writable permissions
1. Main container starts with `GH_CONFIG_DIR=/tmp/gh-config`
1. `gh` reads and writes `hosts.yml` freely (config migration succeeds)
1. `gh` writes `config.yml` and state files to writable emptyDir
1. Every 30s, sidecar re-copies `hosts.yml` from secret mount — token stays fresh across rotations
1. `chmod 666` ensures main container (different UID) can write to the file

### Main Container Mount Changes

The main container(s) `(name): "?*"` volumeMounts update:

| Mount                | Before               | After                                       |
| -------------------- | -------------------- | ------------------------------------------- |
| `github-gh-config`   | `mountPath: /etc/gh` | `mountPath: /etc/gh-secret`                 |
| `gh-config-writable` | —                    | `mountPath: /tmp/gh-config` (new, writable) |

### Key Design Decisions

- **Copy not symlink**: `gh` rewrites `hosts.yml` during config migration. Symlinks follow through to the read-only secret volume, causing write failures.
- **Native sidecar not init container**: Token rotates every 30min. A one-time init copy goes stale for persistent pods. The sidecar refreshes every 30s.
- **chmod 666**: Sidecar runs as UID 65534 (nobody), main container runs as a different UID. Without world-writable permissions, the main container gets permission denied on `hosts.yml`.
- **30s refresh interval**: Well within the 30min rotation window. Low overhead (single small file copy).

## File Changed

| File                                                                | Change                                                                                                                              |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml` | Modify `inject-shared-config` rule: add emptyDir volume, add native sidecar, move secret mount path, update `GH_CONFIG_DIR` env var |

## Testing

1. Spawn a test agent pod in `claude-agents-sre` namespace
1. Verify pod shows 2/2 Running (main container + sidecar)
1. Verify `gh auth status` succeeds — authenticated as `spruyt-labs-bot`
1. Wait 40s, verify `gh auth status` still succeeds (token stable)
1. Confirmed working 2026-04-26
