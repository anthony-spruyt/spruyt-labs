# OpenClaw Smart Git Credential Dispatcher

**Issue:** [#517](https://github.com/anthony-spruyt/spruyt-labs/issues/517)
**Date:** 2026-02-22

## Problem

`init-workspace.sh` writes two separate credential helpers and two `[credential]` sections in `.gitconfig`. Git's URL-scoped credential section matching ignores the path component by default, so the general `https://github.com` helper always wins — `GIT_WORKSPACE_TOKEN` never gets used for workspace repo operations, causing 403s.

## Root Cause

`useHttpPath = true` was not set. Without it, git never passes the repo path to credential helpers, so URL-scoped credential sections cannot discriminate between repos on the same host.

## Solution

Replace two credential helper scripts with a single smart dispatcher that routes tokens by repo path.

### Changes (single file: `init-workspace.sh`)

1. **Remove** the `CREDENTIAL_HELPER_GH` variable and its helper script
2. **Replace** the credential helper with a smart dispatcher that reads `path=` from stdin and routes: `openclaw-workspace` → `$GIT_WORKSPACE_TOKEN`, everything else → `$GH_TOKEN`
3. **Replace** the two `.gitconfig` credential sections with one section using `useHttpPath = true`
4. **Clean up** the orphaned `.git-credential-helper-gh` file from existing PVCs

### Credential Helper

```sh
#!/bin/sh
case "$1" in
  get)
    input=$(cat)
    path=$(echo "$input" | grep '^path=' | cut -d= -f2-)
    if echo "$path" | grep -q "openclaw-workspace"; then
      token="$GIT_WORKSPACE_TOKEN"
    else
      token="$GH_TOKEN"
    fi
    echo "protocol=https"
    echo "host=github.com"
    echo "username=x-access-token"
    echo "password=$token"
    ;;
esac
```

### Git Config

```ini
[credential "https://github.com"]
    helper = /home/node/.openclaw/.git-credential-helper
    useHttpPath = true
[user]
    name = OpenClaw Agent
    email = openclaw@noreply
[pull]
    ff = only
```

## Why This Works

- `useHttpPath = true` causes git to include `path=<owner>/<repo>.git` in credential requests
- The helper reads the `path=` field and routes to the correct token
- Existing PVCs work without migration: both `.git-credential-helper` and `.gitconfig` are overwritten on every init container startup

## What Doesn't Change

- `values.yaml`, `kustomization.yaml`, `entrypoint.sh`, `init-config.sh` — untouched
- Workspace sync logic — untouched
- Credential helper file path — same location, new contents
