#!/bin/bash
set -euo pipefail

# Show flows to or from a specific namespace
# Usage: ./hubble-flows-ns.sh <namespace>

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
NAMESPACE="${1:?Usage: $0 <namespace>}"
hubble_relay observe --namespace "$NAMESPACE" --last 100
