#!/bin/bash
set -euo pipefail

# renovate: depName=@agentmemory/agentmemory datasource=npm
VERSION="0.9.12"

npx --yes "@agentmemory/agentmemory@${VERSION}" --no-engine
