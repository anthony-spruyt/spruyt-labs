# OpenClaw Commit Signing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Sign all OpenClaw agent git commits with an SSH Ed25519 key so GitHub marks them as "Verified" and branch protection ("Require signed commits") is satisfied.

**Architecture:** A custom Kubernetes volume mounts only `id_signing` from the existing `openclaw-workspace-config` secret at `/home/node/.openclaw/.ssh/` with mode `0600` — the conventional SSH key path. `init-workspace.sh` writes a `.gitconfig` that enables SSH signing via that key. No new secret, no copy step, no GPG binary needed.

**Tech Stack:** Kubernetes secret volumes (items + mode), bjw-s app-template `type: custom` persistence, git SSH signing (`gpg.format = ssh`, `commit.gpgSign = true`), Ed25519.

**Design doc:** `docs/plans/2026-02-22-openclaw-commit-signing-design.md`

---

## Pre-flight: Create GitHub Issue

Before touching code, create a tracking issue.

**Step 1: Check for existing issue**

```bash
gh issue list --repo anthony-spruyt/spruyt-labs --search "openclaw commit signing"
```

Expected: no results.

**Step 2: Create issue**

```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "feat(openclaw): add SSH commit signing" \
  --label "enhancement" \
  --body "$(cat <<'EOF'
## Summary
Add SSH commit signing to the OpenClaw agent so commits are marked as Verified by GitHub and satisfy branch protection rules that require signed commits.

## Motivation
The openclaw-workspace repo (and others the agent commits to) blocks unverified commits via branch protection. The agent currently pushes unsigned commits.

## Acceptance Criteria
- OpenClaw agent commits show the GitHub "Verified" badge
- Commits pass repos with "Require signed commits" branch protection enabled
- Private key stored in existing SOPS-encrypted secret (no new secret)
- No manual steps required after initial key registration

## Affected Area
Apps (cluster/apps/)
EOF
)"
```

Note the issue number — use it in all commit messages as `Ref #<number>`.

---

## Task 1: Add signing-key volume to `values.yaml`

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/values.yaml:241-254` (after `workspace-config-files` block)

**Step 1: Open the file and locate the persistence section**

Read `cluster/apps/openclaw/openclaw/app/values.yaml`. The `persistence:` section starts at line 218. The `workspace-config-files` block ends at line 254. Insert the new block after it, before the `# Scripts` comment.

**Step 2: Add the `signing-key` persistence block**

Insert after line 254 (after the closing line of `workspace-config-files`):

```yaml
  # SSH signing key for git commit signing (mode 0600 required by ssh-keygen)
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

**Why `type: custom` with `items`:** The bjw-s `type: secret` with `subPath` ignores `defaultMode` — files land at `0644`. SSH private keys must be `0600` or `ssh-keygen` refuses them with "Permissions too open". The `items` array in a raw volume spec applies per-file mode correctly.

**Why only `init-workspace` and `main`:** `init-workspace` writes the gitconfig that references the key path. `main` is where Claude Code runs and makes commits. `init-config` and `init-skills` don't perform git commits.

**Step 3: Verify YAML is valid**

```bash
python3 -c "import yaml; yaml.safe_load(open('cluster/apps/openclaw/openclaw/app/values.yaml'))" && echo "YAML valid"
```

Expected: `YAML valid`

**Step 4: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/values.yaml
git commit -m "feat(openclaw): mount SSH signing key from workspace-config secret

Ref #<issue-number>"
```

---

## Task 2: Update `init-workspace.sh` gitconfig

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/init-workspace.sh:53-62` (the `cat > "$GITCONFIG"` heredoc)

**Step 1: Locate the gitconfig heredoc**

The current `.gitconfig` template is at lines 53–62 of `init-workspace.sh`:

```sh
cat > "$GITCONFIG" <<GITCONF
[credential "https://github.com"]
    helper = $CREDENTIAL_HELPER
    useHttpPath = true
[user]
    name = OpenClaw Agent
    email = openclaw@noreply
[pull]
    ff = only
GITCONF
```

**Step 2: Replace the heredoc with the signing-enabled version**

Replace the entire `cat > "$GITCONFIG"` block (lines 53–62) with:

```sh
cat > "$GITCONFIG" <<GITCONF
[credential "https://github.com"]
    helper = $CREDENTIAL_HELPER
    useHttpPath = true
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
GITCONF
```

**What each new line does:**

| Setting | Effect |
|---------|--------|
| `email = 99536297+...` | GitHub noreply email matching the account that owns the signing key — required for the "Verified" badge |
| `user.signingKey` | Path to the SSH private key file (mounted from secret at `0600`) |
| `commit.gpgSign = true` | Auto-sign every commit; no need for `-S` flag |
| `gpg.format = ssh` | Tell git to use `ssh-keygen` for signing instead of GPG |

**Step 3: Verify the script is still valid shell**

```bash
sh -n cluster/apps/openclaw/openclaw/app/init-workspace.sh && echo "Shell syntax OK"
```

Expected: `Shell syntax OK`

**Step 4: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/init-workspace.sh
git commit -m "feat(openclaw): configure SSH commit signing in gitconfig

- Update user.email to GitHub noreply format for Verified badge
- Add user.signingKey pointing to /home/node/.openclaw/.ssh/id_signing
- Enable commit.gpgSign = true and gpg.format = ssh

Ref #<issue-number>"
```

---

## Task 3: Update `README.md`

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/README.md`

**Step 1: Find the right location**

Read the README. Insert a new `### Commit Signing` subsection inside the `## Operation` section, after the existing `### Workspace` subsection and before `### Config Changes`.

**Step 2: Add the section**

```markdown
### Commit Signing

OpenClaw signs every git commit with a dedicated Ed25519 SSH key. GitHub verifies the signature against the public key registered on the account and marks commits as **Verified**. This satisfies branch protection rules that require signed commits.

**Initial setup (one-time, performed locally):**

1. Generate a dedicated Ed25519 key pair (no passphrase):

   ```bash
   ssh-keygen -t ed25519 -C "OpenClaw Agent" -f /tmp/openclaw-signing -N ""
   ```

2. Add the private key to the SOPS secret:

   ```bash
   sops cluster/apps/openclaw/openclaw/app/openclaw-workspace-config.sops.yaml
   # Add field: id_signing: |
   #   <paste full PEM content of /tmp/openclaw-signing, including header and footer lines>
   ```

3. Register the public key on GitHub as a **Signing Key** (not Authentication):
   - Go to GitHub → Settings → SSH and GPG keys → New SSH key
   - Key type: **Signing Key**
   - Paste contents of `/tmp/openclaw-signing.pub`

4. Clean up local key files:

   ```bash
   rm /tmp/openclaw-signing /tmp/openclaw-signing.pub
   ```

**How it works:**

- The private key is mounted from `openclaw-workspace-config` at `/home/node/.openclaw/.ssh/id_signing` with mode `0600`
- `init-workspace` writes a `.gitconfig` with `commit.gpgSign = true` and `gpg.format = ssh`
- At commit time, git calls `ssh-keygen -Y sign` using the mounted key
- The commit author email (`99536297+anthony-spruyt@users.noreply.github.com`) matches the GitHub account where the signing key is registered

**Verifying signing works:**

```bash
kubectl exec -it -n openclaw deploy/openclaw -c main -- \
  git -C /home/node/.openclaw/workspace log --show-signature -1
```

Look for `Good "git" signature` in the output.
```

**Step 3: Commit**

```bash
git add cluster/apps/openclaw/openclaw/README.md
git commit -m "docs(openclaw): document SSH commit signing setup

Ref #<issue-number>"
```

---

## Task 4: Run qa-validator

**Step 1: Run the validator**

Use the `qa-validator` agent (per project rules — mandatory before any commit that modifies cluster files).

If BLOCKED, apply the reported fixes and re-run until APPROVED.

---

## Task 5: User action — add key to secret and register on GitHub

This task is performed by the user, not Claude.

**Step 1: Generate key pair locally**

```bash
ssh-keygen -t ed25519 -C "OpenClaw Agent" -f /tmp/openclaw-signing -N ""
```

**Step 2: Add private key to SOPS secret**

```bash
sops cluster/apps/openclaw/openclaw/app/openclaw-workspace-config.sops.yaml
```

Add the field `id_signing` with the full PEM content of `/tmp/openclaw-signing` (including the header and footer lines). In YAML, use a literal block scalar (`id_signing: |`) and paste the key content indented by 2 spaces.

**Step 3: Register public key on GitHub**

- Go to: github.com → Settings → SSH and GPG keys → New SSH key
- Title: `OpenClaw Agent`
- Key type: **Signing Key** (critical — not Authentication)
- Key: paste contents of `/tmp/openclaw-signing.pub`

**Step 4: Clean up**

```bash
rm /tmp/openclaw-signing /tmp/openclaw-signing.pub
```

**Step 5: Push changes and restart pod**

```bash
git push
# Wait for Flux to reconcile and pod to restart
kubectl rollout restart deployment/openclaw -n openclaw
kubectl rollout status deployment/openclaw -n openclaw
```

---

## Task 6: Verify signing works end-to-end

**Step 1: Check init-workspace logs for .ssh mount**

```bash
kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c init-workspace | tail -20
```

Expected: no errors related to gitconfig or credential setup.

**Step 2: Verify key is mounted with correct permissions**

```bash
kubectl exec -n openclaw deploy/openclaw -c main -- \
  ls -la /home/node/.openclaw/.ssh/
```

Expected: `id_signing` present with permissions `-r--------` (mode `0400`) or `-rw-------` (mode `0600`).

**Step 3: Verify gitconfig has signing config**

```bash
kubectl exec -n openclaw deploy/openclaw -c main -- \
  git config --global --list
```

Expected output includes:
```
user.email=99536297+anthony-spruyt@users.noreply.github.com
user.signingkey=/home/node/.openclaw/.ssh/id_signing
commit.gpgsign=true
gpg.format=ssh
```

**Step 4: Check most recent commit signature**

```bash
kubectl exec -n openclaw deploy/openclaw -c main -- \
  git -C /home/node/.openclaw/workspace log --show-signature -1
```

Expected output includes `Good "git" signature`.

**Step 5: Verify on GitHub**

Open `github.com/anthony-spruyt/openclaw-workspace/commits/main` and confirm the most recent agent commit shows the **Verified** badge.

**Step 6: Close the issue**

```bash
gh issue close <number> --repo anthony-spruyt/spruyt-labs \
  --comment "SSH commit signing implemented. Commits from OpenClaw agent now show Verified on GitHub."
```
