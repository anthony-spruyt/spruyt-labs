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

A separate private GitHub repo (e.g. `anthony-spruyt/openclaw-workspace`) holds the workspace contents. The agent pushes its changes here during operation. The user can also push changes that the agent picks up on next restart or pull.

### Init Container: `init-workspace`

A new init container using `alpine/git` runs **before** `init-config` in the pod startup sequence.

**Ordering:**
1. `init-workspace` - clone/pull workspace from git
2. `init-config` - merge openclaw.json config
3. `init-skills` - install ClawHub skills and runtimes

**Logic:**
1. Write a git credential helper to `/home/node/.openclaw/.git-credential-helper` that echoes `GIT_WORKSPACE_TOKEN` from the environment
2. Configure `~/.gitconfig` on the PVC with the credential helper and git user identity (`OpenClaw Agent` / `openclaw@noreply`)
3. If `/home/node/.openclaw/workspace/.git` exists: `git pull --ff-only origin main`
   - On failure (conflicts, diverged history): log warning, continue with existing workspace
4. If no `.git`: `git clone $GIT_WORKSPACE_REPO /home/node/.openclaw/workspace`
   - On failure (empty repo, network): `mkdir -p` the workspace dir, log error, continue

**Key principle:** Never fail the init container. OpenClaw creates bootstrap files if the workspace is empty, so a failed sync is recoverable. A failed init container blocks the entire pod.

**Mounts:**
- PVC `openclaw-data` at `/home/node/.openclaw` (read-write)
- emptyDir at `/tmp` (git scratch space)
- Scripts ConfigMap at `/scripts` (read-only)

**Environment:**
- `GIT_WORKSPACE_TOKEN` - from `openclaw-secrets` (fine-grained PAT, Contents read/write on workspace repo)
- `GIT_WORKSPACE_REPO` - from `openclaw-secrets` (e.g. `https://github.com/anthony-spruyt/openclaw-workspace.git`)

### Git Authentication

The credential helper pattern keeps the token out of `.git/config`:

```sh
# /home/node/.openclaw/.git-credential-helper
#!/bin/sh
echo "protocol=https"
echo "host=github.com"
echo "username=x-access-token"
echo "password=$GIT_WORKSPACE_TOKEN"
```

The `.gitconfig` on the PVC references this helper. Both the init container and the main container use it - the init container for clone/pull, the agent for push during operation. The existing `GH_TOKEN` (read-only, used by `gh` CLI) is unaffected since `gh` and `git` use separate auth mechanisms.

### Security Context

The init container matches the existing security posture:
- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- `capabilities.drop: [ALL]`
- Runs as UID 1000 (matches pod security context)

### Sensitive Workspace Files

Some workspace files contain secrets (e.g. `config/mcporter.json` with MCP API keys and auth tokens). These cannot be committed to the workspace repo.

**Approach:** A small `openclaw-workspace-config` ConfigMap (via `configMapGenerator`) holds only the sensitive files. The `init-config.sh` workspace copy section is updated (not removed) to handle subdirectory paths using `mkdir -p` instead of `basename`. These files are gitignored in the workspace repo.

The workspace repo's `.gitignore` should include:
```
config/mcporter.json
```

## Changes

### Remove

| File | What |
|------|------|
| `kustomization.yaml` | `openclaw-workspace` configMapGenerator entry (replaced by smaller `openclaw-workspace-config`) |
| `values.yaml` | `workspace-files` persistence entry (replaced by `workspace-config-files`) |
| `workspace/*` | All files under `cluster/apps/openclaw/openclaw/app/workspace/` |

### Add

| File | What |
|------|------|
| `init-workspace.sh` | New script: git clone/pull with credential helper |
| `kustomization.yaml` | `init-workspace.sh` added to `openclaw-scripts` configMapGenerator |
| `kustomization.yaml` | `openclaw-workspace-config` configMapGenerator with sensitive files only (e.g. `config/mcporter.json=workspace/config/mcporter.json`) |
| `values.yaml` | `init-workspace` init container definition |
| `values.yaml` | `workspace-config-files` persistence mount for the sensitive files ConfigMap |
| `.gitignore` | Ignore `workspace/` directory (sync task still downloads here) |

### Modify

| File | What |
|------|------|
| `openclaw-secrets.sops.yaml` | User adds `GIT_WORKSPACE_TOKEN` and `GIT_WORKSPACE_REPO` |
| `values.yaml` | Mount scripts, PVC, and tmp into `init-workspace` |
| `init-config.sh` | Replace `basename` flattening with `mkdir -p` + path-preserving copy for sensitive workspace files |

### Unchanged

| File | Why |
|------|-----|
| `sync-workspace.sh` | Stays as local download tool, outputs to gitignored `workspace/` |
| `init-skills.sh` | No changes needed |
| `entrypoint.sh` | No changes needed |

## Agent Configuration

After the workspace repo is created, the agent's `AGENTS.md` should be updated to instruct it to commit and push workspace changes to the remote. The credential helper (set up by the init container) handles auth transparently.

## Rollback

If the init container fails or the approach doesn't work:
1. Re-add the `openclaw-workspace` configMapGenerator entry
2. Restore workspace files from git history
3. Re-add the workspace copy logic to `init-config.sh`
4. Remove the `init-workspace` init container

The PVC retains the workspace regardless, so data is never lost.
