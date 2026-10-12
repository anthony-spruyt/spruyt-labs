#!/usr/bin/env bats
#
# The LiteLLM MCP tool drift script passes its unit tests and covers every server in the committed config. Ref #3493

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
DRIFT_DIR="${REPO_ROOT}/cluster/apps/litellm/litellm/mcp-tool-drift"

@test "PyYAML is available for the config tests" {
  run python3 -c 'import yaml'
  [ "${status}" -eq 0 ]
}

@test "drift script unit tests pass" {
  PYTHONDONTWRITEBYTECODE=1 run python3 -m unittest discover -s "${DRIFT_DIR}" -p 'test_*.py'
  echo "${output}"
  [ "${status}" -eq 0 ]
}
