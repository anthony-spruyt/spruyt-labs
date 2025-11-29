#!/usr/bin/env bash
set -euo pipefail

# Runs mega-linter against the current dev container workspace files,
# excluding pipeline-only environment variables.

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
  -v "/home/aspruyt/.kilocode:/tmp/lint/.kilocode" \
  --rm \
  oxsecurity/megalinter:v9

# Copy fixed changes back to workspace root
if compgen -G "/workspaces/spruyt-labs/.output/updated_sources/*" > /dev/null; then
    cp -r --preserve=all /workspaces/spruyt-labs/.output/updated_sources/* /workspaces/spruyt-labs/
fi

exit 0
