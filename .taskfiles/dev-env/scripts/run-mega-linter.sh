#!/usr/bin/env bash
set -euo pipefail

# Runs mega-linter against the repository.
# Can be run from any directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

rm -rf "$REPO_ROOT/.output"
mkdir "$REPO_ROOT/.output"

docker run \
  -a STDOUT \
  -a STDERR \
  -u "$(id -u):$(id -g)" \
  -w /tmp/lint \
  -e HOME=/tmp \
  -e APPLY_FIXES="all" \
  -e UPDATED_SOURCES_REPORTER="true" \
  -e REPORT_OUTPUT_FOLDER="/tmp/lint/.output" \
  -v "$REPO_ROOT:/tmp/lint" \
  --rm \
  oxsecurity/megalinter:v9

# Capture MegaLinter exit code
LINT_EXIT_CODE=$?

# Copy fixed files back to workspace
if compgen -G "$REPO_ROOT/.output/updated_sources/*" > /dev/null; then
    cp -r "$REPO_ROOT/.output/updated_sources"/* "$REPO_ROOT/"
fi

exit $LINT_EXIT_CODE
