#!/bin/bash
set -euo pipefail

ensure_helm_diff_plugin() {
  # extract only the plugin names (skip header), then look for "diff"
  if helm plugin list | tail -n +2 | awk '{print $1}' | grep -Fxq diff; then
    echo "✅ helm-diff plugin is already installed: $(helm diff version)"
  else
    echo "🔧 helm-diff plugin not found. Installing now..."
    helm plugin install https://github.com/databus23/helm-diff --verify=false
    echo "→ $(helm diff version)"
  fi
}

ensure_helm_schema_gen_plugin() {
  # extract only the plugin names (skip header), then look for "diff"
  if helm plugin list | tail -n +2 | awk '{print $1}' | grep -Fxq schema-gen; then
    echo "✅ helm-schema-gen plugin is already installed"
  else
    echo "🔧 helm-schema-gen plugin not found. Installing now..."
    helm plugin install https://github.com/knechtionscoding/helm-schema-gen --verify=false
  fi
}

ensure_helm_diff_plugin
ensure_helm_schema_gen_plugin
