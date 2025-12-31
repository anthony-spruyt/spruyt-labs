#!/bin/bash
set -euo pipefail

# Run Cilium connectivity test (creates test namespace)
cilium connectivity test --test-namespace cilium-test
