#!/bin/bash
set -euo pipefail

# Run Cilium connectivity test
# Uses dev-debug (privileged PSA) to avoid PodSecurity issues
# Note: Creates temporary test resources, cleaned up on success
# On failure, manually clean up: kubectl delete ns -l cilium.io/connectivity-test=true
cilium connectivity test --test-namespace dev-debug
