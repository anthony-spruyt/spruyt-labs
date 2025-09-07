#!/bin/bash
set -euo pipefail

echo "🔍 Checking installed Helm plugins..."
plugins=$(helm plugin list | awk 'NR>1 {print $1}')

if [ -z "$plugins" ]; then
  echo "⚠️ No Helm plugins found. Nothing to update."
  exit 0
fi

echo "🔄 Updating Helm plugins..."
for plugin in $plugins; do
  echo "➡️ Updating: $plugin"
  helm plugin update "$plugin"
done

echo "✅ All Helm plugins updated."
