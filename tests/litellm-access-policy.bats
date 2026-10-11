#!/usr/bin/env bats
#
# The LiteLLM access-policy reconcile script passes its unit tests and the committed policy file parses. Ref #3484

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
POLICY_DIR="${REPO_ROOT}/cluster/apps/litellm/litellm/access-policy"

@test "PyYAML is available for the policy file tests" {
  run python3 -c 'import yaml'
  [ "${status}" -eq 0 ]
}

@test "reconcile script unit tests pass" {
  PYTHONDONTWRITEBYTECODE=1 run python3 -m unittest discover -s "${POLICY_DIR}" -p 'test_*.py'
  echo "${output}"
  [ "${status}" -eq 0 ]
}
