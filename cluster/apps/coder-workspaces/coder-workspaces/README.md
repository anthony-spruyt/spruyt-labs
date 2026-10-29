# coder-workspaces - Shared config and secrets for Coder workspace pods

## Overview

The namespace Coder workspaces run in. This holds the Secrets, ConfigMaps, RBAC and network policies the templates in `coder-system/coder-template-sync` mount into each workspace pod.

## Operations

### Claude subscription token

`coder-workspace-env-common` carries `CLAUDE_CODE_OAUTH_TOKEN`, so Claude in every workspace uses the subscription through the LiteLLM passthrough without a login per rebuild ([#3344](https://github.com/anthony-spruyt/spruyt-labs/issues/3344)). The token from `claude setup-token` lasts a year. To rotate it, run `claude setup-token`, then `sops set` the new value into
`stringData.CLAUDE_CODE_OAUTH_TOKEN` of that file, and restart workspaces.
