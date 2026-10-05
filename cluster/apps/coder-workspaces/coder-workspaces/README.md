# coder-workspaces - Shared config and secrets for Coder workspace pods

## Overview

The namespace Coder workspaces run in. This holds the Secrets, ConfigMaps, RBAC and network policies the templates in `coder-system/coder-template-sync` mount into each workspace pod.

## Operations

### Happy template keys

`coder-happy-<template>.sops.yaml` (one each for spruyt-labs, xfg, devcontainer) holds a Happy CLI credential under the key `access.key`. Workspaces from that template link it into `~/.happy`, so they start paired ([#3339](https://github.com/anthony-spruyt/spruyt-labs/issues/3339)). Each file is a separate pairing with its own account token. Current Happy apps pair with a derived key, so the file
doesn't hold the account secret.

The key belongs to the self-hosted [Happy server](../../happy-system/happy-server/README.md); a key paired against any other server fails to authenticate. To create or rotate them, run this on home Wi-Fi and scan each QR code with the Happy app. The key never reaches the terminal:

```bash
task happy:rotate-template-keys # all three, or template=xfg for one
```

Running workspaces pick up a rotated key through the symlink. A workspace paired by hand keeps its own key. Rotating doesn't revoke the old pairing's token.

### Claude subscription token

`coder-workspace-env-common` carries `CLAUDE_CODE_OAUTH_TOKEN`, so Claude in every workspace uses the subscription through the LiteLLM passthrough without a login per rebuild ([#3344](https://github.com/anthony-spruyt/spruyt-labs/issues/3344)). The token from `claude setup-token` lasts a year. To rotate it, run `claude setup-token`, then `sops set` the new value into
`stringData.CLAUDE_CODE_OAUTH_TOKEN` of that file, and restart workspaces.
