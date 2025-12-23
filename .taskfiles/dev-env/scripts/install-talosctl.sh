#!/bin/bash
set -euo pipefail

# Remove existing binary to force fresh download (version updates)
if [[ -f /usr/local/bin/talosctl ]]; then
  sudo rm -f /usr/local/bin/talosctl
fi

curl -sL https://talos.dev/install | sh
