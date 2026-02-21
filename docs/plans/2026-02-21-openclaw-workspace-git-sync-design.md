# OpenClaw Workspace Git Sync

Replace ConfigMap-based workspace seeding with a git clone/pull init container. The workspace lives in a separate private repo, enabling bidirectional sync: the agent pushes changes, the user pushes changes, and the init container pulls on pod startup.

## Context

The OpenClaw agent's workspace (`/home/node/.openclaw/workspace`) contains markdown files, skills, config, and memory. Currently, a subset of these files are declared in a Kustomize `configMapGenerator` and copied into the workspace by `init-config.sh` on startup. This approach has limitations:

- ConfigMaps have a 1MB size limit
- Subdirectory structure is lost (the copy script uses `basename`)
- Every new file must be manually added to the configMapGenerator
- Binary files (images) count against the limit

The workspace already has a `.git` directory (created by the agent per OpenClaw docs). A git-based approach scales naturally, preserves directory structure, and enables bidirectional collaboration.

## Design

### Workspace Repository

A separate private GitHub repo (`anthony-spruyt/openclaw-workspace`) holds the workspace contents. The agent pushes its changes here during operation. The user can also push changes that the agent picks up on next restart or pull.

### Init Container: `init-workspace`

A new init container using `alpine/git` runs **before** `init-config` in the pod startup sequence. Ordering is enforced via `dependsOn` (bjw-s app-template uses topological sort, not YAML insertion order).

**Ordering (enforced via `dependsOn`):**
1. `init-workspace` - clone/pull workspace from git
2. `init-config` (`dependsOn: init-workspace`) - merge openclaw.json config, copy sensitive files
3. `init-skills` (`dependsOn: init-config`) - install ClawHub skills and runtimes

**Logic:**
1. Write a git credential helper to `/home/node/.openclaw/.git-credential-helper` (on PVC) and `chmod +x` it
2. Write `.gitconfig` to `/home/node/.openclaw/.gitconfig` (on PVC) with credential helper, user identity, and `pull.ff = only`
3. If `/home/node/.openclaw/workspace/.git` exists: `git pull --ff-only origin main`
   - On failure (conflicts, diverged history, uncommitted changes): log warning, continue with existing workspace
4. If workspace directory exists but has no `.git`: remove it (`rm -rf`), then clone
5. If no workspace directory: `git clone $GIT_WORKSPACE_REPO /home/node/.openclaw/workspace`
   - On failure (empty repo, network): `mkdir -p` the workspace dir, log error, continue

**Key principle:** Never fail the init container. OpenClaw creates bootstrap files if the workspace is empty, so a failed sync is recoverable. A failed init container blocks the entire pod.

**Environment:**
- `HOME=/home/node/.openclaw` - Required because `readOnlyRootFilesystem: true` prevents writing to `/home/node/`. Setting HOME to the PVC mount ensures `~/.gitconfig` and credential helper resolve to writable paths.
- `GIT_WORKSPACE_TOKEN` - from `openclaw-secrets` via `envFrom`
- `GIT_WORKSPACE_REPO` - from `openclaw-secrets` via `envFrom`

**Mounts (reuses existing pod volumes):**
- PVC `openclaw-data` at `/home/node/.openclaw` (read-write) - added to existing `data` advancedMounts
- Shared `tmp` emptyDir at `/tmp` - added to existing `tmp` advancedMounts
- Scripts ConfigMap at `/scripts` (read-only) - added to existing `scripts` advancedMounts

### Git Authentication

The credential helper pattern keeps the token out of `.git/config`:

```sh
# /home/node/.openclaw/.git-credential-helper
#!/bin/sh
# Git credential protocol: only respond to 'get' requests
case "$1" in
  get)
    echo "protocol=https"
    echo "host=github.com"
    echo "username=x-access-token"
    echo "password=$GIT_WORKSPACE_TOKEN"
    ;;
esac
```

The helper is written to the PVC using a **quoted heredoc** (`<<'HELPER'`) so `$GIT_WORKSPACE_TOKEN` remains as a literal variable reference in the file. It is resolved at invocation-time when git calls the helper, not at write-time. This means the token is never stored in plaintext on the PVC.

**Requirement:** `GIT_WORKSPACE_TOKEN` must be available in the environment of any container that uses `git push/pull`. The main container already satisfies this via `envFrom: secretRef: openclaw-secrets` (see `values.yaml`).

The `.gitconfig` on the PVC references this helper. Both the init container and the main container use it - the init container for clone/pull, the agent for push during operation.

**Main container requirement:** The main container must set `GIT_CONFIG_GLOBAL=/home/node/.openclaw/.gitconfig` in its env so the agent's git operations find the credential helper. Without this, git defaults to `$HOME/.gitconfig` which is on the read-only root filesystem.

The existing `GH_TOKEN` (read-only, used by `gh` CLI) is unaffected since `gh` and `git` use separate auth mechanisms.

**Non-interactive safety:** `GIT_TERMINAL_PROMPT=0` must be set in `init-workspace.sh` to prevent git from hanging on credential prompts if the token is misconfigured. This causes git to fail fast instead.

### Security Context

The init container matches the existing security posture:
- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- `capabilities.drop: [ALL]`
- Runs as UID 1000 (matches pod security context)

### Network Policies

The existing `allow-world-egress` CiliumNetworkPolicy allows all-port egress to `world` for the openclaw pod. Cilium enforces at the pod level, so init containers inherit the same policy. No new network policy is needed.

### Sensitive Workspace Files

Some workspace files contain secrets (e.g. `config/mcporter.json` with MCP API keys and auth tokens). These cannot be committed to the workspace repo.

**Approach:** A small `openclaw-workspace-config` ConfigMap (via `configMapGenerator`) holds only the sensitive files with flat key names (e.g. key `mcporter.json` sourced from `workspace/config/mcporter.json`). The ConfigMap is mounted at `/workspace-config-files` (read-only) in the `init-config` container. The `init-config.sh` copies files from `/workspace-config-files/` to their correct workspace paths using explicit mappings. These files are gitignored in the workspace repo.

The workspace repo's `.gitignore` includes:
```
config/mcporter.json
```

**Bootstrap on fresh repo clone:** The `workspace/config/mcporter.json` file is gitignored in this repo. After a fresh clone, it must be restored before `kustomize build` can succeed. Restore from the running pod:
```bash
kubectl cp openclaw/<pod>:/home/node/.openclaw/workspace/config/mcporter.json \
  cluster/apps/openclaw/openclaw/app/workspace/config/mcporter.json
```

## Changes

### Remove

| File | What |
|------|------|
| `kustomization.yaml` | `openclaw-workspace` configMapGenerator entry (replaced by smaller `openclaw-workspace-config`) |
| `values.yaml` | `workspace-files` persistence entry (replaced by `workspace-config-files`) |
| `workspace/*` | All files under `cluster/apps/openclaw/openclaw/app/workspace/` (removed from git tracking) |

### Add

| File | What |
|------|------|
| `init-workspace.sh` | New script: git clone/pull with credential helper |
| `kustomization.yaml` | `init-workspace.sh` added to `openclaw-scripts` configMapGenerator |
| `kustomization.yaml` | `openclaw-workspace-config` configMapGenerator with flat keys for sensitive files only (`disableNameSuffixHash: true`) |
| `values.yaml` | `init-workspace` init container definition with `dependsOn` ordering |
| `values.yaml` | `workspace-config-files` persistence mount for the sensitive files ConfigMap |
| `.gitignore` | Ignore `workspace/` directory (sync task still downloads here) |

### Modify

| File | What |
|------|------|
| `openclaw-secrets.sops.yaml` | ~~User adds `GIT_WORKSPACE_TOKEN` and `GIT_WORKSPACE_REPO`~~ DONE |
| `values.yaml` | Add `init-workspace` to existing `data`, `scripts`, and `tmp` advancedMounts |
| `values.yaml` | Add `dependsOn: init-workspace` to `init-config`, `dependsOn: init-config` to `init-skills` |
| `values.yaml` | Add `GIT_CONFIG_GLOBAL` and `GIT_TERMINAL_PROMPT=0` env vars to main container |
| `init-config.sh` | Replace workspace file copy with explicit sensitive-file mappings |

### Unchanged

| File | Why |
|------|-----|
| `sync-workspace.sh` | Stays as local download tool for ad-hoc inspection. Output goes to gitignored `workspace/`. Now that the workspace lives in its own repo, the primary workflow for reviewing agent changes is `git pull` from `anthony-spruyt/openclaw-workspace` |
| `init-skills.sh` | No changes needed |
| `entrypoint.sh` | No changes needed |
| `network-policies.yaml` | Existing `allow-world-egress` CNP covers init containers at pod level |

## Agent Configuration

After the workspace repo is created, the agent's `AGENTS.md` should be updated to instruct it to commit and push workspace changes to the remote. The credential helper (set up by the init container) handles auth transparently.

## Rollback

If the init container fails or the approach doesn't work:
1. Re-add the `openclaw-workspace` configMapGenerator entry
2. Restore workspace files from git history
3. Re-add the workspace copy logic to `init-config.sh`
4. Remove the `init-workspace` init container
5. Remove `dependsOn` from `init-config` and `init-skills`
6. Remove `GIT_CONFIG_GLOBAL` and `GIT_TERMINAL_PROMPT` from main container env

The PVC retains the workspace regardless, so data is never lost. Note: the PVC will retain a `.git` directory inside `workspace/` from the clone. This does not affect ConfigMap-based operation but is not cleaned up automatically.
