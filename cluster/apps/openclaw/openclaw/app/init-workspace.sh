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
