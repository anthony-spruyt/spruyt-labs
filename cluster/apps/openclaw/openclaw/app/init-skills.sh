#!/bin/sh
# Init container: skill installation
# Installs ClawHub skills and runtime dependencies (idempotent).
# Skills are installed from https://clawhub.com
set -e

log() { echo "[$(date -Iseconds)] [init-skills] $*"; }

log "Starting skills initialization"

# ============================================================
# Runtime Dependencies
# ============================================================
# Some skills require additional runtimes (Python, Go, etc.)
# Install them here so they persist across pod restarts.
#
# Example: Install uv (Python package manager) for Python skills
# mkdir -p /home/node/.openclaw/bin
# if [ ! -f /home/node/.openclaw/bin/uv ]; then
#   log "Installing uv..."
#   curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/home/node/.openclaw/bin sh
# fi
#
# Example: Install pnpm and packages for interfaces (e.g., MS Teams)
# The read-only filesystem and non-root UID prevent writing to default
# pnpm paths (/usr/local/lib/node_modules, ~/.local/share/pnpm, etc.).
# Redirect PNPM_HOME to the PVC so the binary persists across restarts.
# The init container's HOME=/tmp ensures pnpm's cache, state, and config
# writes land on /tmp (writable emptyDir). The store goes on the PVC so
# hardlinks work (same filesystem as node_modules) and persist.
# PNPM_HOME=/home/node/.openclaw/pnpm
# mkdir -p "$PNPM_HOME"
# if [ ! -f "$PNPM_HOME/pnpm" ]; then
#   log "Installing pnpm..."
#   curl -fsSL https://get.pnpm.io/install.sh | env PNPM_HOME="$PNPM_HOME" SHELL=/bin/sh sh -
# fi
# export PATH="$PNPM_HOME:$PATH"
# log "Installing interface dependencies..."
# cd /home/node/.openclaw
# pnpm install <your-package> --store-dir /home/node/.openclaw/.pnpm-store

BIN_DIR=/home/node/.openclaw/bin
mkdir -p "$BIN_DIR"

# --- Aikido safe-chain (supply chain security) ---
# Intercepts npm/pip/uv/npx installs via a local proxy that checks packages
# against Aikido Intel threat intelligence. Must be set up BEFORE any
# package manager operations (npm, pip, uv) so they are protected.
# renovate: depName=@aikidosec/safe-chain datasource=npm
SAFE_CHAIN_VERSION="1.4.4"
NPM_GLOBAL=/home/node/.openclaw/npm-global
mkdir -p "$NPM_GLOBAL"
if [ ! -f "$NPM_GLOBAL/bin/safe-chain" ]; then
  log "Installing safe-chain v$${SAFE_CHAIN_VERSION}..."
  npm install -g "@aikidosec/safe-chain@$${SAFE_CHAIN_VERSION}" --prefix "$NPM_GLOBAL"
  log "safe-chain installed"
else
  log "safe-chain already installed"
fi
# Create CI shims in $HOME/.safe-chain/shims (HOME=/tmp in init container)
# Re-run every startup since /tmp is ephemeral (emptyDir)
log "Setting up safe-chain shims..."
"$NPM_GLOBAL/bin/safe-chain" setup-ci
export PATH="$HOME/.safe-chain/shims:$HOME/.safe-chain/bin:$NPM_GLOBAL/bin:$PATH"

# --- GitHub CLI (gh) ---
# renovate: depName=cli/cli datasource=github-releases
GH_VERSION="2.87.0"
if [ ! -f "$BIN_DIR/gh" ]; then
  log "Installing GitHub CLI v$${GH_VERSION}..."
  curl -LsSf "https://github.com/cli/cli/releases/download/v$${GH_VERSION}/gh_$${GH_VERSION}_linux_amd64.tar.gz" | tar xz -C /tmp
  cp "/tmp/gh_$${GH_VERSION}_linux_amd64/bin/gh" "$BIN_DIR/gh"
  rm -rf "/tmp/gh_$${GH_VERSION}_linux_amd64"
  log "GitHub CLI installed"
else
  log "GitHub CLI already installed"
fi

# --- Go ---
# renovate: depName=golang/go datasource=github-tags versioning=semver extractVersion=^go(?<version>.+)$
GO_VERSION="1.26.0"
GO_DIR=/home/node/.openclaw/go
if [ ! -d "$GO_DIR" ]; then
  log "Installing Go v$${GO_VERSION}..."
  curl -LsSf "https://go.dev/dl/go$${GO_VERSION}.linux-amd64.tar.gz" | tar xz -C /home/node/.openclaw
  log "Go installed"
else
  log "Go already installed"
fi

# --- Python (via uv) ---
# renovate: depName=astral-sh/uv datasource=github-releases
UV_VERSION="0.10.4"
if [ ! -f "$BIN_DIR/uv" ]; then
  log "Installing uv v$${UV_VERSION}..."
  curl -LsSf "https://astral.sh/uv/$${UV_VERSION}/install.sh" | env UV_INSTALL_DIR="$BIN_DIR" sh
  log "uv installed"
else
  log "uv already installed"
fi

# Install a default Python via uv if not present
PYTHON_DIR=/home/node/.openclaw/python
if [ ! -d "$PYTHON_DIR" ]; then
  log "Installing Python via uv..."
  # UV_PYTHON_INSTALL_DIR: store the cpython build on the PVC
  # --no-bin: skip creating executables in $HOME/.local/bin (HOME=/tmp in init container)
  UV_PYTHON_INSTALL_DIR="$PYTHON_DIR" "$BIN_DIR/uv" python install --no-bin
  log "Python installed"
else
  log "Python already installed"
fi

# Always ensure stable symlinks exist (idempotent)
# uv creates a nested cpython-x.y.z-<platform>/ directory; symlink for stable PATH
if [ ! -f "$PYTHON_DIR/bin/python3" ]; then
  PYTHON_BIN=$(find "$PYTHON_DIR" -name "python3" \( -type f -o -type l \) 2>/dev/null | head -1)
  if [ -n "$PYTHON_BIN" ]; then
    mkdir -p "$PYTHON_DIR/bin"
    ln -sf "$PYTHON_BIN" "$PYTHON_DIR/bin/python3"
    ln -sf "$PYTHON_BIN" "$PYTHON_DIR/bin/python"
    log "Python symlinked at $PYTHON_DIR/bin"
  else
    log "WARNING: Python binary not found for symlinking"
  fi
fi

# --- mcporter (MCP client for Home Assistant etc.) ---
# renovate: depName=mcporter datasource=npm
MCPORTER_VERSION="0.7.3"
if [ ! -f "$NPM_GLOBAL/bin/mcporter" ]; then
  log "Installing mcporter v$${MCPORTER_VERSION}..."
  npm install -g "mcporter@$${MCPORTER_VERSION}" --prefix "$NPM_GLOBAL" --safe-chain-skip-minimum-package-age
  log "mcporter installed"
else
  log "mcporter already installed"
fi
ln -sf "$NPM_GLOBAL/bin/mcporter" "$BIN_DIR/mcporter"

# ============================================================
# Skill Installation
# ============================================================
# Install skills from ClawHub (https://clawhub.com)
# Add skill slugs to the list below to install them declaratively.
mkdir -p /home/node/.openclaw/workspace/skills
cd /home/node/.openclaw/workspace
# add more skill slugs as needed
for skill in weather mcp-hass ontology; do
  if [ -n "$skill" ] && [ ! -d "skills/${skill##*/}" ]; then
    log "Installing skill: $skill"
    if ! npx -y clawhub install "$skill" --no-input; then
      log "WARNING: Failed to install skill: $skill"
    fi
  else
    log "Skill already installed: $skill"
  fi
done
log "Skills initialization complete"
