#!/usr/bin/env bash
set -eo pipefail

bootstrap_from_file() {
  local settings_file="$1"
  [ -f "$settings_file" ] || return 0
  [ -r "$settings_file" ] || {
    echo "[plugin-bootstrap] WARNING: cannot read $settings_file (permission denied)"
    return 1
  }
  jq empty "$settings_file" || {
    echo "[plugin-bootstrap] invalid JSON in $settings_file"
    exit 1
  }
  echo "[plugin-bootstrap] reading $settings_file"

  jq -j '.extraKnownMarketplaces // {} | to_entries[] | select(.value.source != null and .value.source.repo != null) | .key, "\u0000", .value.source.repo, "\u0000"' \
    "$settings_file" | while IFS= read -r -d '' name && IFS= read -r -d '' repo; do
    echo "[plugin-bootstrap] marketplace add: $name ($repo)"
    claude plugins marketplace add "$repo" --scope user ||
      echo "[plugin-bootstrap] WARNING: failed to add marketplace '$name'"
  done

  jq -j '.enabledPlugins // {} | to_entries[] | select(.value == true or .value == "true") | .key, "\u0000"' \
    "$settings_file" | while IFS= read -r -d '' plugin; do
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

for settings_file in "$@"; do
  bootstrap_from_file "$settings_file"
done

echo "[plugin-bootstrap] done"
