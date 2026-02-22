# OpenClaw Smart Credential Dispatcher Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace two broken credential helpers with a single smart dispatcher that routes git tokens by repo path.

**Architecture:** One credential helper script reads `path=` from git's credential protocol stdin and routes `openclaw-workspace` requests to `$GIT_WORKSPACE_TOKEN`, everything else to `$GH_TOKEN`. A single `.gitconfig` credential section with `useHttpPath = true` enables path-based routing.

**Tech Stack:** Shell script, git credential protocol, Kustomize ConfigMap

**Issue:** [#517](https://github.com/anthony-spruyt/spruyt-labs/issues/517)

**Design:** [docs/plans/2026-02-22-openclaw-credential-dispatcher-design.md](./2026-02-22-openclaw-credential-dispatcher-design.md)

---

### Task 1: Replace credential helpers with smart dispatcher

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/init-workspace.sh:11-48`

**Step 1: Remove `CREDENTIAL_HELPER_GH` variable**

Remove line 12 (`CREDENTIAL_HELPER_GH=...`).

**Step 2: Replace both helper scripts with the smart dispatcher**

Replace lines 14-48 (from the `# Git Credential Helper` comment block through `chmod +x "$CREDENTIAL_HELPER_GH"`) with:

```sh
# ============================================================
# Git Credential Helper
# ============================================================
# Single dispatcher: routes by repo path.
# openclaw-workspace → GIT_WORKSPACE_TOKEN, all others → GH_TOKEN.
# Requires useHttpPath = true in .gitconfig so git passes the path.
log "Configuring git credential helper"
cat > "$CREDENTIAL_HELPER" <<'HELPER'
#!/bin/sh
# Routes by repo path: openclaw-workspace → GIT_WORKSPACE_TOKEN, else → GH_TOKEN
case "$1" in
  get)
    input=$(cat)
    path=$(echo "$input" | grep '^path=' | cut -d= -f2-)
    if echo "$path" | grep -q "openclaw-workspace"; then
      token="$GIT_WORKSPACE_TOKEN"
    else
      token="$GH_TOKEN"
    fi
    echo "protocol=https"
    echo "host=github.com"
    echo "username=x-access-token"
    echo "password=$token"
    ;;
esac
HELPER
chmod +x "$CREDENTIAL_HELPER"
```

**Step 3: Verify the edit**

Run: Read tool on `init-workspace.sh` and confirm:
- No reference to `CREDENTIAL_HELPER_GH` variable
- No second helper script block
- Smart dispatcher reads `path=` from stdin
- Heredoc uses `<<'HELPER'` (quoted, so `$` vars expand at runtime, not write-time)

---

### Task 2: Replace gitconfig credential sections

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/init-workspace.sh:50-64`

**Step 1: Replace the two credential sections with one**

Replace lines 50-64 (from `# Git Configuration` comment block through `GITCONF`) with:

```sh
# ============================================================
# Git Configuration
# ============================================================
# Write .gitconfig on the PVC (shared with main container via GIT_CONFIG_GLOBAL).
# useHttpPath = true is critical: without it git never passes the repo path
# to the credential helper, so it cannot discriminate between repos.
cat > "$GITCONFIG" <<GITCONF
[credential "https://github.com"]
    helper = $CREDENTIAL_HELPER
    useHttpPath = true
[user]
    name = OpenClaw Agent
    email = openclaw@noreply
[pull]
    ff = only
GITCONF
```

**Step 2: Verify the edit**

Run: Read tool on `init-workspace.sh` and confirm:
- Single `[credential "https://github.com"]` section (not path-scoped)
- `useHttpPath = true` is present
- `helper` points to `$CREDENTIAL_HELPER` (the single dispatcher)
- `[user]` and `[pull]` sections unchanged

---

### Task 3: Validate and commit

**Step 1: Read the complete file**

Run: Read tool on `init-workspace.sh` to review the full final state.

**Step 2: Run qa-validator**

Run qa-validator agent to check the changes before committing.

**Step 3: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/init-workspace.sh
git commit -m "fix(openclaw): smart git credential dispatcher with useHttpPath routing

Replace two credential helpers with a single dispatcher that reads
the repo path from git's credential protocol and routes tokens:
openclaw-workspace → GIT_WORKSPACE_TOKEN, all others → GH_TOKEN.

Key fix: useHttpPath = true enables git to pass the repo path to the
helper, which was the root cause of 403s on workspace pushes.

Closes #517"
```
