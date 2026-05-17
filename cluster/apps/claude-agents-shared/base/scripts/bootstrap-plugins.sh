#!/usr/bin/env bash
set -eo pipefail

REPO_DIR="/workspace/repo"

bootstrap_from_file() {
  local settings_file="$1"
  [ -f "$settings_file" ] || return 0
  jq empty "$settings_file" || {
    echo "[plugin-bootstrap] invalid JSON in $settings_file"
    exit 1
  }
  echo "[plugin-bootstrap] reading $settings_file"

  jq -r '.extraKnownMarketplaces // {} | to_entries[] | select(.value.source != null and .value.source.repo != null) | "\(.key)\t\(.value.source.repo)"' \
    "$settings_file" | while IFS="$(printf '\t')" read -r name repo; do
    echo "[plugin-bootstrap] marketplace add: $name ($repo)"
    claude plugins marketplace add "$repo" --scope user ||
      echo "[plugin-bootstrap] WARNING: failed to add marketplace '$name'"
  done

  jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true or .value == "true") | .key' \
    "$settings_file" | while IFS= read -r plugin; do
    echo "[plugin-bootstrap] install: $plugin"
    claude plugins install "$plugin" --scope user ||
      echo "[plugin-bootstrap] WARNING: failed to install '$plugin'"
  done
}

command -v jq >/dev/null || {
  echo "[plugin-bootstrap] jq not found"
  exit 1
}
command -v claude >/dev/null || {
  echo "[plugin-bootstrap] claude CLI not found"
  exit 1
}

# Cluster-managed settings (from ConfigMap)
bootstrap_from_file "/etc/claude-code/managed-settings.json"

# User-level settings (on claude-home emptyDir — empty in fresh pods)
bootstrap_from_file "$HOME/.claude/settings.json"

# Project-level settings (from cloned repo)
bootstrap_from_file "$REPO_DIR/.claude/settings.json"
bootstrap_from_file "$REPO_DIR/.claude/settings.local.json"

echo "[plugin-bootstrap] done"
