#!/bin/bash
set -euo pipefail

# renovate: datasource=npm depName=@agentmemory/agentmemory
VERSION="0.9.12"

npx --yes "@agentmemory/agentmemory@${VERSION}" --no-engine
