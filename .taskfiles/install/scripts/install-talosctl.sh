#!/bin/bash
set -euo pipefail

# Remove existing binary to force fresh download (version updates)
if [[ -f /usr/local/bin/talosctl ]]; then
  sudo rm -f /usr/local/bin/talosctl
fi

curl --proto '=https' --tlsv1.2 -sSLf https://talos.dev/install | sh
