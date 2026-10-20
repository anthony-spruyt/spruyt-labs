#!/bin/bash
set -euo pipefail

# Stream dropped flows in real-time
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hubble_relay observe --verdict DROPPED -f
