#!/usr/bin/env bash
set -euo pipefail

cd /workspaces/spruyt-labs/capacitor
./next --port 3333 --kubeconfig "/workspaces/spruyt-labs/secrets/kubeconfig"
