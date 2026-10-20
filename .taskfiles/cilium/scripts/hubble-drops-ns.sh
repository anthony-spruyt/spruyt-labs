#!/bin/bash
set -euo pipefail

# Show drops to or from a specific namespace
# Usage: ./hubble-drops-ns.sh <namespace>

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
NAMESPACE="${1:?Usage: $0 <namespace>}"
hubble_relay observe --verdict DROPPED --namespace "$NAMESPACE" --last 100
