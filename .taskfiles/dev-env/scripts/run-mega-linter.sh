#!/usr/bin/env bash
set -euo pipefail

# Runs mega-linter against the current dev container workspace files,
# excluding pipeline-only environment variables.
#
# NOTE: The -v mount path must match the HOST filesystem (WSL), not the devcontainer.
# Update /home/aspruyt if your WSL username differs.

sudo rm -rf /workspaces/spruyt-labs/.output
mkdir /workspaces/spruyt-labs/.output

sudo docker run \
  -a STDOUT \
  -a STDERR \
  -u root:root \
  -w /tmp/lint \
  -e APPLY_FIXES="all" \
  -e UPDATED_SOURCES_REPORTER="true" \
  -e REPORT_OUTPUT_FOLDER="/tmp/lint/.output" \
  -v "/home/aspruyt/spruyt-labs:/tmp/lint" \
  --rm \
  oxsecurity/megalinter:v9

# Capture MegaLinter exit code
LINT_EXIT_CODE=$?

# Copy fixed changes back to workspace root
# Use sudo because megalinter runs as root and creates root-owned files
if compgen -G "/workspaces/spruyt-labs/.output/updated_sources/*" > /dev/null; then
    sudo cp -r /workspaces/spruyt-labs/.output/updated_sources/* /workspaces/spruyt-labs/
    # Fix ownership so git can work with the files
    sudo chown -R "$(id -u):$(id -g)" /workspaces/spruyt-labs/
fi

# Return MegaLinter's actual exit code so qa-validator sees failures
exit $LINT_EXIT_CODE
