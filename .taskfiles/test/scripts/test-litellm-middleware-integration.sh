#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
MIDDLEWARE_DIR="${ROOT_DIR}/cluster/apps/litellm/litellm/app/plugins/middleware"
export PYTHONDONTWRITEBYTECODE=1

if ! uv --version >/dev/null 2>&1; then
  echo "❌ uv not found. Run: task install:uv-cli"
  exit 1
fi

# Coder workspaces must not run third-party images through plain docker.
if [ -z "${LITELLM_IT_RUNNER:-}" ] && command -v agent-run >/dev/null 2>&1; then
  export LITELLM_IT_RUNNER=agent-run
fi

cd "${MIDDLEWARE_DIR}"
uv run --extra dev --frozen --no-build pytest integration "$@"
