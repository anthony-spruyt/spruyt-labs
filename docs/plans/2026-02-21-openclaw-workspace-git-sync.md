# OpenClaw Workspace Git Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace ConfigMap-based workspace seeding with a git clone/pull init container so the OpenClaw workspace lives in its own repo with bidirectional sync.

**Architecture:** New `init-workspace` init container using `alpine/git` clones on first boot, fast-forward pulls on restart. Git credential helper on the PVC enables both init container and agent to authenticate. A small `openclaw-workspace-config` ConfigMap handles sensitive files (e.g. `config/mcporter.json`) that cannot go in the workspace repo. Init container ordering is enforced via `dependsOn`.

**Tech Stack:** Kubernetes init containers, alpine/git, git credential helpers, SOPS secrets, Kustomize configMapGenerator

**Design doc:** `docs/plans/2026-02-21-openclaw-workspace-git-sync-design.md`

**Issue:** #502

---

## Prerequisites (User Actions) - ALL DONE

1. ~~Create private GitHub repo `anthony-spruyt/openclaw-workspace`~~ DONE
2. ~~Push current workspace contents to the repo (excluding sensitive files)~~ DONE
3. ~~Add `.gitignore` to workspace repo excluding `config/mcporter.json`~~ DONE
4. ~~Create a fine-grained PAT scoped to the workspace repo with Contents read/write~~ DONE
5. ~~Add `GIT_WORKSPACE_TOKEN` and `GIT_WORKSPACE_REPO` to `openclaw-secrets.sops.yaml`~~ DONE

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
# Git credential protocol: only respond to 'get' requests
case "$1" in
  get)
    echo "protocol=https"
    echo "host=github.com"
    echo "username=x-access-token"
    echo "password=$GIT_WORKSPACE_TOKEN"
    ;;
esac
HELPER
chmod +x "$CREDENTIAL_HELPER"

# ============================================================
# Git Configuration
# ============================================================
# Write .gitconfig on the PVC (shared with main container via GIT_CONFIG_GLOBAL).
cat > "$GITCONFIG" <<GITCONF
[credential]
    helper = $CREDENTIAL_HELPER
[user]
    name = OpenClaw Agent
    email = openclaw@noreply
[pull]
    ff = only
GITCONF

# Use GIT_CONFIG_GLOBAL so git finds config regardless of HOME
export GIT_CONFIG_GLOBAL="$GITCONFIG"

# Prevent git from hanging on credential prompts in non-interactive containers
export GIT_TERMINAL_PROMPT=0

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
    log "WARNING: Pull failed (conflicts, diverged history, or uncommitted changes), continuing with existing workspace"
  fi
elif [ -d "$WORKSPACE" ]; then
  # Workspace directory exists but has no .git - remove and clone fresh
  log "WARNING: Non-git workspace directory found, removing to clone fresh"
  rm -rf "$WORKSPACE"
  if git clone "$GIT_WORKSPACE_REPO" "$WORKSPACE" 2>&1; then
    log "Workspace cloned successfully"
  else
    log "WARNING: Clone failed, creating empty workspace directory"
    mkdir -p "$WORKSPACE"
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

### Task 2: Update kustomization.yaml

**Prerequisite:** Verify `cluster/apps/openclaw/openclaw/app/workspace/config/mcporter.json` exists on disk. The new `openclaw-workspace-config` configMapGenerator references this file. If absent, `kustomize build` will fail, blocking Flux reconciliation.

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/kustomization.yaml`

**Step 1: Add init-workspace.sh to openclaw-scripts configMapGenerator**

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

**Step 2: Replace openclaw-workspace configMapGenerator with openclaw-workspace-config**

Remove the old `openclaw-workspace` entry and replace with:

```yaml
  - name: openclaw-workspace-config
    namespace: openclaw
    options:
      disableNameSuffixHash: true
    files:
      - mcporter.json=workspace/config/mcporter.json
```

Note: The key is `mcporter.json` (flat), not `config/mcporter.json`. Keys with `/` create unmountable ConfigMap volumes.

**Step 3: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/kustomization.yaml
git commit -m "feat(openclaw): update kustomization for workspace git sync

Add init-workspace.sh to scripts ConfigMap. Replace bulk
openclaw-workspace ConfigMap with openclaw-workspace-config
for sensitive files only.

Ref #502"
```

---

### Task 3: Update init-config.sh

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/init-config.sh`

**Step 1: Replace workspace file copy section (lines 70-81)**

Remove the old generic loop and replace with explicit sensitive-file mappings:

```bash
# ============================================================
# Workspace Config Files (sensitive files from ConfigMap)
# ============================================================
# These files contain secrets and are not stored in the workspace git repo.
# They are injected via ConfigMap and copied to the correct workspace paths.
log "Syncing sensitive workspace config files from ConfigMap"
if [ -f /workspace-config-files/mcporter.json ]; then
  mkdir -p "/home/node/.openclaw/workspace/config"
  cp /workspace-config-files/mcporter.json "/home/node/.openclaw/workspace/config/mcporter.json"
  log "Writing workspace/config/mcporter.json"
fi
log "Workspace config sync complete"
```

**Step 2: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/init-config.sh
git commit -m "feat(openclaw): update init-config.sh for sensitive workspace files

Replace basename-flattening loop with explicit path mappings
for sensitive files injected via ConfigMap.

Ref #502"
```

---

### Task 4: Update values.yaml

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/values.yaml`

**Step 1: Add init-workspace init container**

Add before `init-config` in `controllers.main.initContainers`:

```yaml
      # Init container: git clone/pull workspace from private repo.
      # Runs before init-config to ensure workspace is populated.
      # Script: init-workspace.sh (mounted from openclaw-scripts ConfigMap)
      init-workspace:
        image:
          # renovate: image=alpine/git
          repository: alpine/git
          tag: "2.47.2"
        command:
          - sh
          - /scripts/init-workspace.sh
        env:
          HOME: /home/node/.openclaw
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

**Step 2: Add dependsOn to init-config and init-skills**

```yaml
      init-config:
        dependsOn: init-workspace
        image:
          ...
      init-skills:
        dependsOn: init-config
        image:
          ...
```

**Step 3: Add git env vars to main container**

The main container needs `GIT_CONFIG_GLOBAL` so the agent's git operations find the credential helper on the PVC, and `GIT_TERMINAL_PROMPT=0` to prevent git from hanging on credential prompts if the helper is misconfigured:

```yaml
      main:
        ...
        env:
          GIT_CONFIG_GLOBAL: /home/node/.openclaw/.gitconfig
          GIT_TERMINAL_PROMPT: "0"
```

**Step 4: Replace workspace-files persistence with workspace-config-files**

Remove the old `workspace-files` entry:

```yaml
  # DELETE THIS:
  workspace-files:
    type: configMap
    name: openclaw-workspace
    advancedMounts:
      main:
        init-config:
          - path: /workspace-files
            readOnly: true
```

Add the new entry:

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

**Step 5: Add init-workspace to existing persistence advancedMounts**

For `data` (PVC) - add `init-workspace` entry:
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

For `scripts` - add `init-workspace` entry:
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

For `tmp` - add `init-workspace` entry:
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

**Step 6: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/values.yaml
git commit -m "feat(openclaw): add init-workspace container and update values

- Add init-workspace init container with alpine/git
- Add dependsOn for init container ordering
- Add GIT_CONFIG_GLOBAL to main container
- Replace workspace-files with workspace-config-files persistence
- Add init-workspace to data, scripts, tmp advancedMounts

Ref #502"
```

---

### Task 5: Remove workspace files from git tracking

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/.gitignore` (already exists with `workspace/`)
- Delete from tracking: all files under `cluster/apps/openclaw/openclaw/app/workspace/`

**Step 1: Remove workspace files from git tracking**

The `.gitignore` already exists with `workspace/`. Remove the tracked files:

```bash
git rm -r --cached cluster/apps/openclaw/openclaw/app/workspace/
```

Note: This must run AFTER Task 2 (which removes the old configMapGenerator references to `workspace/*.md` files). The `workspace/config/mcporter.json` file must remain on disk (not tracked by git) since the new configMapGenerator references it.

**Step 2: Commit**

Note: `git rm -r --cached` from Step 1 already stages the file deletions. The `git add` below only stages the `.gitignore`. Both the staged deletions and the `.gitignore` will be included in the commit.

```bash
git add cluster/apps/openclaw/openclaw/app/.gitignore
git commit -m "chore(openclaw): remove workspace files from git tracking

Workspace now lives in anthony-spruyt/openclaw-workspace.
Sensitive files are injected via ConfigMap from local copies.
Directory is gitignored; sync task still downloads here.

Ref #502"
```

---

### Task 6: Run qa-validator

**Step 1: Run qa-validator to validate all changes**

Use the qa-validator agent to check syntax, schemas, and standards.

Expected: APPROVED (or fix any issues flagged)

---

### Task 7: User post-implementation steps

1. Push all changes to main
2. Verify pod starts with all init containers passing
3. Check init-workspace logs: `kubectl logs -n openclaw <pod> -c init-workspace`
4. Verify the agent can commit and push to the workspace repo
5. Update `AGENTS.md` in workspace repo to instruct agent to commit/push workspace changes
