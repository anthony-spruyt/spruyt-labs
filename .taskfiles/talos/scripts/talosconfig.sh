#!/bin/bash
set -euo pipefail

# `topf talosconfig` prints the config to stdout. Capture it straight to clusterconfig/ -
# gitignored, and denied to AI agents - instead of letting client certs land in a terminal
# scrollback. --redact=false is belt and braces: this command writes with fmt.Println and
# bypasses the masking writer, so redaction does not apply to it today.
TALOSCONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/talos/clusterconfig/talosconfig"

umask 077
bash "$(dirname "$0")/topf.sh" --redact=false talosconfig >"${TALOSCONFIG}"

if talosctl config merge "${TALOSCONFIG}"; then
  echo "Merged talosconfig into local talosctl config"
else
  echo "Skipped talosctl config merge (config may be read-only)"
fi

talosctl config info
