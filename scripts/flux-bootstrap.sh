#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

./flux-install.sh

eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

flux bootstrap git \
  --url="ssh://git@github.com/${GIT_OWNER}/${GIT_REPO}.git" \
  --branch=${GIT_BRANCH} \
  --path=${GIT_PATH}

#echo "🔑 If you see authentication errors on GitHub, add this Flux deploy key as a write-access deploy key to your repository:"
#kubectl -n flux-system get secret flux-system -o jsonpath="{.data['identity\.pub']}" | base64 -d || echo "(No deploy key found - Flux may still be starting or bootstrapping failed)"
