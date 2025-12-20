#!/usr/bin/env bash
set -euo pipefail

capacitor-next --port 3333 --kubeconfig "/home/vscode/.secrets/kubeconfig"
