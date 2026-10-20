#!/bin/bash
set -euo pipefail

# Show Hubble status and flow buffer capacity across all nodes
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hubble_relay status
