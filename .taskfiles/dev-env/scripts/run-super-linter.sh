#!/usr/bin/env bash
set -euo pipefail

# Runs super-linter against the current dev container workspace files,
# excluding pipeline-only environment variables.
sudo docker run \
  -a STDOUT \
  -a STDERR \
  -u root:root \
  -e DEFAULT_BRANCH="main" \
  -e FILTER_REGEX_EXCLUDE=".*sops.*|.*/mcp\.json$" \
  -e FIX_MARKDOWN_PRETTIER="true" \
  -e FIX_MARKDOWN="true" \
  -e FIX_NATURAL_LANGUAGE="true" \
  -e FIX_YAML_PRETTIER="true" \
  -e IGNORE_GITIGNORED_FILES="true" \
  -e LINTER_RULES_PATH=".github/linters" \
  -e RUN_LOCAL="true" \
  -e SAVE_SUPER_LINTER_OUTPUT="true" \
  -e SUPER_LINTER_OUTPUT_DIRECTORY_NAME=".output" \
  -e USE_FIND_ALGORITHM="false" \
  -e VALIDATE_ALL_CODEBASE="true" \
  -e VALIDATE_BASH="true" \
  -e VALIDATE_BASH_EXEC="true" \
  -e VALIDATE_GITHUB_ACTIONS="true" \
  -e VALIDATE_GITLEAKS="true" \
  -e VALIDATE_JSON="true" \
  -e VALIDATE_JSON_PRETTIER="true" \
  -e VALIDATE_JSONC="true" \
  -e VALIDATE_JSONC_PRETTIER="true" \
  -e VALIDATE_NATURAL_LANGUAGE="true" \
  -e VALIDATE_MARKDOWN="true" \
  -e VALIDATE_MARKDOWN_PRETTIER="true" \
  -e VALIDATE_RENOVATE="true" \
  -e VALIDATE_TERRAFORM_FMT="true" \
  -e VALIDATE_TERRAFORM_TFLINT="true" \
  -e VALIDATE_TRIVY="true" \
  -e VALIDATE_YAML="true" \
  -e VALIDATE_YAML_PRETTIER="true" \
  -v "/home/aspruyt/spruyt-labs:/tmp/lint" \
  --rm \
  ghcr.io/super-linter/super-linter:slim-latest

# -e VALIDATE_CHECKOV="true" \ # Cant get this one working locally
# -e VALIDATE_TERRAFORM_TERRASCAN="true" \ # Do not need doubling up
