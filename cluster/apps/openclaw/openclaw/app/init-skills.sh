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

# ============================================================
# Skill Installation
# ============================================================
# Install skills from ClawHub (https://clawhub.com)
# Add skill slugs to the list below to install them declaratively.
mkdir -p /home/node/.openclaw/workspace/skills
cd /home/node/.openclaw/workspace
# shellcheck disable=SC2043  # Single-item loop is intentional; add more skill slugs as needed
for skill in weather; do
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
