#!/bin/bash
set -euo pipefail

# Show only policy-related drops
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hubble_relay observe --verdict DROPPED --type policy-verdict --last 100
