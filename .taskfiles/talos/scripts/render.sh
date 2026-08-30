#!/bin/bash
set -euo pipefail

# clusterconfig/ is gitignored and denied to AI agents; keep rendered plaintext there.
bash "$(dirname "$0")/topf.sh" render -o clusterconfig/topf "$@"
