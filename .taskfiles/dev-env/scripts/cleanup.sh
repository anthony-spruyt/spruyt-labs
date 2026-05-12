#!/usr/bin/env bash
set -euo pipefail

echo "=== Dev environment cleanup ==="
echo ""

# --- Podman ---
if command -v podman &>/dev/null; then
  echo ">> Podman: pruning all images, containers, and build cache..."
  if sudo podman system prune --all --force 2>&1; then
    sudo podman system df
  else
    echo "   podman prune failed (namespace/uid issue?) — try running directly: podman system prune --all --force"
  fi
  echo ""
fi

# --- /tmp cloned repos and work dirs ---
echo ">> Cleaning known /tmp work directories..."
tmp_dirs=(
  /tmp/container-images
  /tmp/xfg
  /tmp/SunGather
  /tmp/claude-config
  /tmp/repo-operator
  /tmp/firemerge
  /tmp/claude-plugins
  /tmp/n8n-nodes-claude-code-cli
  /tmp/velero-chart
  /tmp/n8n-chart
  /tmp/renovate
  /tmp/megalinter-reports
)
for d in "${tmp_dirs[@]}"; do
  if [[ -d "$d" ]]; then
    size=$(du -sh "$d" 2>/dev/null | cut -f1)
    rm -rf "$d"
    echo "   removed $d ($size)"
  fi
done

# --- /tmp anonymous temp dirs (tmp.XXXXX) ---
echo ">> Cleaning anonymous /tmp/tmp.* directories..."
find /tmp -maxdepth 1 -name 'tmp.*' -type d -mmin +60 -exec rm -rf {} + 2>/dev/null || true

# --- Stale hookify state files (>1h old, skip current session) ---
echo ">> Cleaning stale hookify state files..."
hookify_count=$(find /tmp -maxdepth 1 -name 'claude-hookify-state-*.json' -type f -mmin +60 2>/dev/null | wc -l)
if [[ "$hookify_count" -gt 0 ]]; then
  find /tmp -maxdepth 1 -name 'claude-hookify-state-*.json' -type f -mmin +60 -delete 2>/dev/null || true
  echo "   removed $hookify_count stale hookify state files (>1h old)"
else
  echo "   none stale (skipping recent/active sessions)"
fi

# --- Go/node caches ---
echo ">> Cleaning build caches..."
if command -v go &>/dev/null; then
  go clean -cache 2>/dev/null && echo "   go cache cleaned" || true
fi
rm -rf /tmp/node-compile-cache 2>/dev/null && echo "   node compile cache cleaned" || true

# --- Summary ---
echo ""
echo "=== Disk usage ==="
df -h / | tail -1 | awk '{print "Used: "$3" / "$2" ("$5" full), Free: "$4}'
echo ""
echo "Done."
