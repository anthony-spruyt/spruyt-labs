#!/bin/bash
set -euo pipefail

# Capture to gitignored, agent-denied clusterconfig/ so client certs never reach scrollback.
# --redact=false keeps the captured config complete if topf ever redacts this command.
TALOSCONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/talos/clusterconfig/talosconfig"

umask 077
bash "$(dirname "$0")/topf.sh" --redact=false talosconfig >"${TALOSCONFIG}"

if talosctl config merge "${TALOSCONFIG}"; then
  echo "Merged talosconfig into local talosctl config"
else
  echo "Skipped talosctl config merge (config may be read-only)"
fi

talosctl config info
