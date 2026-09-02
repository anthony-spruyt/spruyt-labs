#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
PLUGINS_DIR="${ROOT_DIR}/cluster/apps/litellm/litellm/app/plugins"
export PYTHONDONTWRITEBYTECODE=1

# safe-chain ships a permanent uv shim on PATH, so command -v always succeeds
if ! uv --version >/dev/null 2>&1; then
  echo "❌ uv not found. Run: task install:uv-cli"
  exit 1
fi

status=0
for manifest in "${PLUGINS_DIR}"/*/pyproject.toml; do
  plugin_dir="$(dirname "${manifest}")"
  echo "=== $(basename "${plugin_dir}") ==="
  # cd so pytest resolves rootdir from the plugin's pyproject.toml, not the repo root.
  # --frozen fails instead of silently relocking, so a stale uv.lock surfaces here.
  # --no-build refuses sdists, so no dependency's build backend executes locally.
  if ! (cd "${plugin_dir}" && uv run --extra dev --frozen --no-build pytest); then
    status=1
  fi
  echo ""
done

exit "${status}"
