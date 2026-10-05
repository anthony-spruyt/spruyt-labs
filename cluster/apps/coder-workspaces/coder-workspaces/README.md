# coder-workspaces - Shared config and secrets for Coder workspace pods

## Overview

The namespace Coder workspaces run in. This holds the Secrets, ConfigMaps, RBAC and network policies the templates in `coder-system/coder-template-sync` mount into each workspace pod.

## Operations

### Happy template keys

`coder-happy-<template>.sops.yaml` (one each for spruyt-labs, xfg, devcontainer) holds a Happy CLI credential under the key `access.key`. Workspaces from that template link it into `~/.happy`, so they start paired ([#3339](https://github.com/anthony-spruyt/spruyt-labs/issues/3339)). Each file is a separate pairing with its own account token. Current Happy apps pair with a derived key, so the file
doesn't hold the account secret.

To create or rotate one, run this from the repo root and pair when prompted. The key never reaches the terminal:

```bash
t=xfg # or spruyt-labs, devcontainer
dir=cluster/apps/coder-workspaces/coder-workspaces/app
h=$(mktemp -d)
(
  set -eo pipefail
  HAPPY_HOME_DIR=$h npx -y happy auth login
  kubectl create secret generic "coder-happy-$t" -n coder-workspaces \
    --from-file="access.key=$h/access.key" --dry-run=client -o yaml |
    sops -e --filename-override "$dir/coder-happy-$t.sops.yaml" \
      --input-type yaml --output-type yaml /dev/stdin >"$h/enc.yaml"
  mv "$h/enc.yaml" "$dir/coder-happy-$t.sops.yaml"
)
rm -rf "$h"
```

Running workspaces pick up a rotated key through the symlink. A workspace paired by hand keeps its own key. Rotating doesn't revoke the old pairing's token.
