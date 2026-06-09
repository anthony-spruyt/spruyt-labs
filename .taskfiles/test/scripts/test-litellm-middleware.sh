#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
VENV_DIR="${LITELLM_MIDDLEWARE_TEST_VENV:-/tmp/litellm-middleware-tests}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
export PYTHONDONTWRITEBYTECODE=1

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  "${PYTHON_BIN}" -m venv "${VENV_DIR}"
fi

if ! "${VENV_DIR}/bin/python" - <<'PY' >/dev/null 2>&1; then
import httpx
import pytest
import pytest_asyncio
PY
  "${VENV_DIR}/bin/python" -m pip install --quiet --disable-pip-version-check \
    pytest \
    pytest-asyncio \
    httpx
fi

"${VENV_DIR}/bin/python" -m pytest \
  "${ROOT_DIR}/cluster/apps/litellm/litellm/app/plugins"
