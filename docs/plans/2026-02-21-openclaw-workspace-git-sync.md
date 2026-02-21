# OpenClaw Workspace Git Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace ConfigMap-based workspace seeding with a git clone/pull init container so the OpenClaw workspace lives in its own repo with bidirectional sync.

**Architecture:** New `init-workspace` init container using `alpine/git` clones on first boot, fast-forward pulls on restart. Git credential helper on the PVC enables both init container and agent to authenticate. The bulk `openclaw-workspace` ConfigMap is replaced by a small `openclaw-workspace-config` ConfigMap for sensitive files only (e.g. `config/mcporter.json`). The `init-config.sh` copy logic is updated to preserve subdirectory paths.

**Tech Stack:** Kubernetes init containers, alpine/git, git credential helpers, SOPS secrets, Kustomize configMapGenerator

**Design doc:** `docs/plans/2026-02-21-openclaw-workspace-git-sync-design.md`

**Issue:** #502

---

## Prerequisites (User Actions)

Before implementation begins, the user must complete these manual steps:

1. Create private GitHub repo `anthony-spruyt/openclaw-workspace`
2. Push current workspace contents to the repo (excluding sensitive files like `config/mcporter.json`)
3. Add `.gitignore` to workspace repo excluding sensitive files (e.g. `config/mcporter.json`)
4. Create a fine-grained PAT scoped to the workspace repo with Contents read/write
5. ~~Add `GIT_WORKSPACE_TOKEN` and `GIT_WORKSPACE_REPO` to `openclaw-secrets.sops.yaml` using `sops`~~ DONE

---

### Task 1: Create `init-workspace.sh` script

**Files:**
- Create: `cluster/apps/openclaw/openclaw/app/init-workspace.sh`

**Step 1: Write the init-workspace.sh script**

```bash
#!/bin/sh
# Init container: workspace git sync
# Clones workspace repo on first boot, fast-forward pulls on restart.
# Never fails - a missing workspace is recoverable (OpenClaw bootstraps defaults).
set -e

log() { echo "[$(date -Iseconds)] [init-workspace] $*"; }

WORKSPACE="/home/node/.openclaw/workspace"
GITCONFIG="/home/node/.openclaw/.gitconfig"
CREDENTIAL_HELPER="/home/node/.openclaw/.git-credential-helper"

# ============================================================
# Git Credential Helper
# ============================================================
# Write credential helper that reads token from environment.
# Persists on PVC so the main container can also use it.
log "Configuring git credential helper"
cat > "$CREDENTIAL_HELPER" <<'HELPER'
#!/bin/sh
echo "protocol=https"
echo "host=github.com"
echo "username=x-access-token"
echo "password=$GIT_WORKSPACE_TOKEN"
HELPER
chmod +x "$CREDENTIAL_HELPER"

# ============================================================
# Git Configuration
# ============================================================
# Write .gitconfig on the PVC (shared with main container).
cat > "$GITCONFIG" <<GITCONF
[credential]
    helper = $CREDENTIAL_HELPER
[user]
    name = OpenClaw Agent
    email = openclaw@noreply
[pull]
    ff = only
GITCONF

# Tell git where to find config (HOME may not be writable)
export GIT_CONFIG_GLOBAL="$GITCONFIG"
export HOME="/tmp"

# ============================================================
# Workspace Sync
# ============================================================
if [ -z "$GIT_WORKSPACE_REPO" ]; then
  log "WARNING: GIT_WORKSPACE_REPO not set, skipping workspace sync"
  mkdir -p "$WORKSPACE"
  exit 0
fi

if [ -d "$WORKSPACE/.git" ]; then
  log "Existing workspace found, pulling latest changes"
  cd "$WORKSPACE"
  if git pull --ff-only origin main 2>&1; then
    log "Workspace updated successfully"
  else
    log "WARNING: Pull failed (conflicts or diverged history), continuing with existing workspace"
  fi
else
  log "No workspace found, cloning from $GIT_WORKSPACE_REPO"
  if git clone "$GIT_WORKSPACE_REPO" "$WORKSPACE" 2>&1; then
    log "Workspace cloned successfully"
  else
    log "WARNING: Clone failed, creating empty workspace directory"
    mkdir -p "$WORKSPACE"
  fi
fi

log "Workspace sync complete"
```

**Step 2: Verify the script is syntactically valid**

Run: `bash -n cluster/apps/openclaw/openclaw/app/init-workspace.sh`
Expected: No output (valid syntax)

**Step 3: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/init-workspace.sh
git commit -m "feat(openclaw): add init-workspace.sh git sync script

Ref #502"
```

---

### Task 2: Add `init-workspace.sh` to `openclaw-scripts` ConfigMap

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/kustomization.yaml`

**Step 1: Add init-workspace.sh to the openclaw-scripts configMapGenerator files list**

In the `openclaw-scripts` configMapGenerator entry (currently has `entrypoint.sh`, `init-config.sh`, `init-skills.sh`), add `init-workspace.sh`:

```yaml
  - name: openclaw-scripts
    namespace: openclaw
    options:
      disableNameSuffixHash: true
    files:
      - entrypoint.sh
      - init-config.sh
      - init-skills.sh
      - init-workspace.sh
```

**Step 2: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/kustomization.yaml
git commit -m "feat(openclaw): add init-workspace.sh to scripts ConfigMap

Ref #502"
```

---

### Task 3: Add `init-workspace` init container to values.yaml

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/values.yaml`

**Step 1: Add init-workspace init container BEFORE init-config**

Insert the new init container block before the existing `init-config` entry in `controllers.main.initContainers`. It must come first so the workspace is available when `init-config` runs.

```yaml
      # Init container: git clone/pull workspace from private repo.
      # Runs before init-config to ensure workspace is populated.
      # Script: init-workspace.sh (mounted from openclaw-scripts ConfigMap)
      init-workspace:
        image:
          repository: alpine/git
          tag: "2.47.2"
        command:
          - sh
          - /scripts/init-workspace.sh
        envFrom:
          - secretRef:
              name: openclaw-secrets
        securityContext:
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - ALL
```

**Note:** Check https://hub.docker.com/r/alpine/git/tags for the latest stable tag. Use a pinned version, not `latest`.

**Step 2: Add persistence mounts for init-workspace**

In the `persistence` section, add `init-workspace` to the mount lists for `data`, `scripts`, and `tmp`.

For `data` (the PVC):
```yaml
  data:
    existingClaim: openclaw-data
    advancedMounts:
      main:
        init-workspace:
          - path: /home/node/.openclaw
        init-config:
          - path: /home/node/.openclaw
        init-skills:
          - path: /home/node/.openclaw
        main:
          - path: /home/node/.openclaw
```

For `scripts`:
```yaml
  scripts:
    type: configMap
    name: openclaw-scripts
    defaultMode: 0755
    advancedMounts:
      main:
        init-workspace:
          - path: /scripts
            readOnly: true
        init-config:
          - path: /scripts
            readOnly: true
        init-skills:
          - path: /scripts
            readOnly: true
        main:
          - path: /scripts
            readOnly: true
```

For `tmp`:
```yaml
  tmp:
    type: emptyDir
    advancedMounts:
      main:
        init-workspace:
          - path: /tmp
        init-config:
          - path: /tmp
        init-skills:
          - path: /tmp
        main:
          - path: /tmp
        chromium:
          - path: /tmp
```

**Step 3: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/values.yaml
git commit -m "feat(openclaw): add init-workspace init container

Ref #502"
```

---

### Task 4: Replace bulk ConfigMap with sensitive-files-only ConfigMap

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/kustomization.yaml`
- Modify: `cluster/apps/openclaw/openclaw/app/init-config.sh`
- Modify: `cluster/apps/openclaw/openclaw/app/values.yaml`

**Step 1: Replace `openclaw-workspace` configMapGenerator in kustomization.yaml**

Remove the old `openclaw-workspace` entry and replace with a smaller one for sensitive files only. Use the `key=path` syntax so keys preserve subdirectory paths:

```yaml
  - name: openclaw-workspace-config
    namespace: openclaw
    options:
      disableNameSuffixHash: true
    files:
      - config/mcporter.json=workspace/config/mcporter.json
```

**Step 2: Update workspace file copy in init-config.sh**

Replace the current workspace copy section (lines 70-81) with a path-preserving version:

```bash
# ============================================================
# Workspace Config Files (sensitive files from ConfigMap)
# ============================================================
# These files contain secrets and are not stored in the workspace git repo.
# They are injected via ConfigMap and copied to the correct workspace paths.
log "Syncing sensitive workspace config files from ConfigMap"
for f in /workspace-config-files/*; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  # Keys may contain paths (e.g. config/mcporter.json) - preserve directory structure
  target="/home/node/.openclaw/workspace/$fname"
  mkdir -p "$(dirname "$target")"
  log "Writing workspace/$fname"
  cp "$f" "$target"
done
log "Workspace config sync complete"
```

**Step 3: Replace `workspace-files` persistence in values.yaml**

Remove the old `workspace-files` entry and replace with:

```yaml
  # Sensitive workspace config files (e.g. MCP credentials) injected via ConfigMap
  workspace-config-files:
    type: configMap
    name: openclaw-workspace-config
    advancedMounts:
      main:
        init-config:
          - path: /workspace-config-files
            readOnly: true
```

**Step 4: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/kustomization.yaml \
        cluster/apps/openclaw/openclaw/app/init-config.sh \
        cluster/apps/openclaw/openclaw/app/values.yaml
git commit -m "feat(openclaw): replace bulk workspace ConfigMap with sensitive-files-only ConfigMap

Non-sensitive workspace files now come from git (init-workspace).
Only files with secrets (e.g. config/mcporter.json) remain in the ConfigMap.

Ref #502"
```

---

### Task 5: Gitignore workspace directory and clean up

**Files:**
- Create or modify: `cluster/apps/openclaw/openclaw/app/.gitignore`
- Delete: all files under `cluster/apps/openclaw/openclaw/app/workspace/`

**Step 1: Create/update .gitignore**

```
workspace/
```

This ensures the sync task can still download to this directory without it being committed.

**Step 2: Remove workspace files from git tracking**

```bash
git rm -r --cached cluster/apps/openclaw/openclaw/app/workspace/
```

This removes the files from git tracking but leaves them on disk (if present). The `.gitignore` prevents them from being re-added.

**Step 3: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/.gitignore
git commit -m "chore(openclaw): gitignore workspace directory and remove tracked files

Workspace now lives in a separate private repo. The sync task
still downloads here for ad-hoc inspection but files are not committed.

Ref #502"
```

---

### Task 6: Run qa-validator

**Step 1: Run qa-validator to validate all changes**

Use the qa-validator agent to check syntax, schemas, and standards before the final commit set.

Expected: APPROVED (or fix any issues flagged)

---

### Task 7: User manual steps

After all code changes are committed, the user must:

1. ~~Create the private workspace repo on GitHub~~ (if not already done)
2. ~~Push workspace contents to the repo (excluding sensitive files)~~ (if not already done)
3. ~~Create a fine-grained PAT with Contents read/write on the workspace repo~~ DONE
4. ~~Add secrets to `openclaw-secrets.sops.yaml`~~ DONE
5. Push all changes to main
6. Verify pod starts with all init containers passing
7. Verify the agent can commit and sync to the workspace repo
