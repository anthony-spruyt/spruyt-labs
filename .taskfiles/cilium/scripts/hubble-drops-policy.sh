#!/bin/bash
set -euo pipefail

# Show drops with policy match info
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hubble_relay observe --verdict DROPPED --last 100 -o compact
