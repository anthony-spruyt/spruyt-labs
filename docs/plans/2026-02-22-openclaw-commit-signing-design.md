# OpenClaw Commit Signing Design

**Date:** 2026-02-22
**Status:** Approved
**Scope:** `cluster/apps/openclaw/`

## Problem

The `anthony-spruyt/openclaw-workspace` repository (and other repos the OpenClaw agent commits to) has branch protection enabled with **"Require signed commits"**. Commits pushed by the agent currently lack a signature and are rejected as unverified.

## Goal

All commits made by the OpenClaw agent are signed with an SSH key registered on GitHub, causing them to display the **Verified** badge and pass branch protection checks.

## Approach

SSH commit signing using a dedicated Ed25519 key pair. Git's native SSH signing support (no GPG binary required) calls `ssh-keygen -Y sign` at commit time. The private key is stored in the existing `openclaw-workspace-config` SOPS secret and mounted directly into the pod at the conventional `.ssh/` path with mode `0600`.

`ssh-keygen` is confirmed present at `/usr/bin/ssh-keygen` in the `ghcr.io/openclaw/openclaw` image.

## Architecture

```
User generates Ed25519 key pair
    ↓
Private key → openclaw-workspace-config secret (id_signing field)
Public key  → GitHub account → Settings → SSH keys → Signing Key
    ↓
Pod starts: Kubernetes mounts secret at /home/node/.openclaw/.ssh/
  - Only id_signing exposed (items filter)
  - mode 0600 enforced by Kubernetes volume spec
    ↓
init-workspace writes .gitconfig with:
  - user.email = 99536297+anthony-spruyt@users.noreply.github.com
  - user.signingKey = /home/node/.openclaw/.ssh/id_signing
  - commit.gpgSign = true
  - gpg.format = ssh
    ↓
main container: git commit → ssh-keygen -Y sign → signed commit
    ↓
git push → GitHub verifies signature → "Verified" badge
```

## Changes

### `values.yaml` — new persistence block

Add a `signing-key` custom volume that mounts only `id_signing` from the existing `openclaw-workspace-config` secret at `/home/node/.openclaw/.ssh/` in both the `init-workspace` init container and the `main` container.

```yaml
signing-key:
  type: custom
  volumeSpec:
    secret:
      secretName: openclaw-workspace-config
      items:
        - key: id_signing
          path: id_signing
          mode: 0600
  advancedMounts:
    main:
      init-workspace:
        - path: /home/node/.openclaw/.ssh
          readOnly: true
      main:
        - path: /home/node/.openclaw/.ssh
          readOnly: true
```

Using `type: custom` with `items` allows mounting a single key from the secret (not the whole secret directory) while applying the exact file mode. The `defaultMode` field on a plain `type: secret` volume does not apply to `subPath` mounts, making `type: custom` with `items` the correct approach.

The `.ssh/` directory is confirmed absent on the PVC — no existing data will be obscured by the mount. Future SSH authentication keys (if PAT is replaced with SSH auth) can be added to the same secret and exposed via additional `items` entries.

### `init-workspace.sh` — gitconfig

Update the `.gitconfig` template with three new stanzas and the correct author email:

```ini
[user]
    name = OpenClaw Agent
    email = 99536297+anthony-spruyt@users.noreply.github.com
    signingKey = /home/node/.openclaw/.ssh/id_signing
[commit]
    gpgSign = true
[gpg]
    format = ssh
[pull]
    ff = only
[credential "https://github.com"]
    helper = /home/node/.openclaw/.git-credential-helper
    useHttpPath = true
```

`user.email` is changed from `openclaw@noreply` to the GitHub noreply format so GitHub can associate the commit author with the account where the signing key is registered, enabling the Verified badge.

### `openclaw-workspace-config.sops.yaml` — user action

Add `id_signing` field containing the PEM content of the Ed25519 private key. This is a user-performed manual step using `sops openclaw-workspace-config.sops.yaml`.

### `README.md` — new section

Document the commit signing setup, key generation command, GitHub registration steps, and the noreply email used.

## User Actions (performed once, outside of code changes)

1. **Generate key pair** (no passphrase):
   ```bash
   ssh-keygen -t ed25519 -C "OpenClaw Agent" -f /tmp/openclaw-signing -N ""
   ```

2. **Add private key to secret:**
   ```bash
   sops cluster/apps/openclaw/openclaw/app/openclaw-workspace-config.sops.yaml
   # Add field: id_signing: <contents of /tmp/openclaw-signing>
   ```

3. **Register public key on GitHub:**
   - Navigate to GitHub → Settings → SSH and GPG keys → New SSH key
   - **Key type: Signing Key** (not Authentication)
   - Paste contents of `/tmp/openclaw-signing.pub`

4. **Clean up:**
   ```bash
   rm /tmp/openclaw-signing /tmp/openclaw-signing.pub
   ```

## Non-Goals

- SSH authentication (HTTPS + token remains for git push/pull)
- GPG signing
- Per-repo signing key rotation
