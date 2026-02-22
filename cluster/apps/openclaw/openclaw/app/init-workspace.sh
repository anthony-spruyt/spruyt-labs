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
      var_name="GIT_WORKSPACE_TOKEN"
    else
      token="$GH_TOKEN"
      var_name="GH_TOKEN"
    fi
    if [ -z "$token" ]; then
      echo "[credential-helper] ERROR: $var_name is not set" >&2
      exit 1
    fi
    echo "protocol=https"
    echo "host=github.com"
    echo "username=x-access-token"
    echo "password=$token"
    ;;
esac
HELPER
chmod +x "$CREDENTIAL_HELPER"

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
  log "Existing workspace found, verifying origin remote"
  cd "$WORKSPACE"

  # Ensure origin remote is set and points to the correct repo
  CURRENT_ORIGIN=$(git remote get-url origin 2>/dev/null || echo "")
  if [ -z "$CURRENT_ORIGIN" ]; then
    log "No origin remote configured, adding it"
    git remote add origin "$GIT_WORKSPACE_REPO"
  elif [ "$CURRENT_ORIGIN" != "$GIT_WORKSPACE_REPO" ]; then
    log "Origin remote URL mismatch, updating to $GIT_WORKSPACE_REPO"
    git remote set-url origin "$GIT_WORKSPACE_REPO"
  fi

  # Ensure local branch is main (app may have init'd with master)
  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "main" ]; then
    log "Renaming branch $CURRENT_BRANCH to main"
    git branch -m "$CURRENT_BRANCH" main 2>&1
  fi

  log "Pulling latest changes"
  if git pull --ff-only origin main 2>&1; then
    log "Workspace updated successfully"
  else
    # Pull failed - untracked file conflicts or diverged history.
    # Force-sync to remote state (remote is source of truth).
    log "WARNING: Pull failed, force-syncing to origin/main"
    git reset --hard origin/main 2>&1
    log "Workspace synced to origin/main"
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
