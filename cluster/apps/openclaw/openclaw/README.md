# OpenClaw - AI Agent Platform

## Overview

OpenClaw is a self-hosted AI agent platform providing a web gateway and Discord bot for interacting with Claude and OpenAI models. It includes a Chromium sidecar for browser automation, extensible skills via ClawHub, MCP tool integrations, and an alertmanager webhook receiver for SRE automation.

OpenClaw does NOT support horizontal scaling - it runs as a single replica with Recreate strategy.

## Prerequisites

- Kubernetes cluster with Flux CD
- Rook Ceph storage provisioned (PVC)
- Traefik ingress controller
- Authentik identity provider (SSO via proxy provider)
- cert-manager for TLS certificates

## Architecture

```text
User -> Traefik (TLS) -> Authentik forward-auth -> OpenClaw gateway (:18789)
                                                        |
Discord <-> OpenClaw agents <-> MCP servers (kubectl, n8n, VictoriaMetrics)
                   |
              Chromium sidecar (:9222, localhost only)

Alertmanager -> webhook hook -> SRE agent -> Discord
```

### Agents

OpenClaw runs multiple specialized agents, each with a tuned model:

| Agent         | Model             | Fallback   | Purpose                        |
| ------------- | ----------------- | ---------- | ------------------------------ |
| main (Skynet) | claude-sonnet-4-6 | gpt-5-mini | Default agent, general purpose |
| monitor       | claude-haiku-4-5  | gpt-5-nano | Lightweight monitoring         |
| researcher    | claude-sonnet-4-6 | gpt-5-mini | Research tasks                 |
| communicator  | claude-opus-4-6   | gpt-5.2    | User-facing communication      |
| coordinator   | claude-opus-4-6   | gpt-5.2    | Multi-agent orchestration      |
| sre           | claude-sonnet-4-6 | gpt-5-mini | SRE automation, alert triage   |

### Security Model

| Layer     | Control                                                                                                                                                                             |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Network   | Cilium CNP: Traefik ingress on 18789, alertmanager ingress on 18789, kubectl-mcp egress on 8000, n8n MCP egress on 5678, VictoriaMetrics MCP egress on 8080, world egress all ports |
| Auth      | Gateway token auth (`OPENCLAW_GATEWAY_TOKEN`), Authentik proxy provider with group-based access (OpenClaw Users) for Control UI                                                     |
| DNS       | Split DNS - LAN-only, no Cloudflare tunnel exposure                                                                                                                                 |
| Container | read-only root filesystem, non-root (UID 1000), all caps dropped, seccomp RuntimeDefault                                                                                            |
| Namespace | PSA restricted (enforce + audit + warn)                                                                                                                                             |

The gateway uses token-based auth for API/CLI connections. The Control UI ignores `gateway.auth.mode` and always uses device pairing ([openclaw#25293](https://github.com/openclaw/openclaw/issues/25293)). Device auth is disabled (`dangerouslyDisableDeviceAuth`) as a workaround. Authentik forward-auth + Cilium network policies provide the actual security layer.

### Discord Integration

OpenClaw's primary user interface is Discord. Configuration:

- **Stream mode**: off (full responses, not streamed)
- **DM policy**: allowlist (owner only)
- **Guild policy**: allowlist with per-channel overrides
- **Thread bindings**: enabled with 72-hour idle TTL
- **Commands**: restricted to owner (`allowFrom`)

### Hooks (Webhooks)

The alertmanager webhook hook routes alerts to the SRE agent:

- **Path**: `/hooks/alertmanager` (authenticated via `OPENCLAW_HOOKS_TOKEN`)
- **Action**: Spawns an SRE agent session keyed by alert `groupKey`
- **Delivery**: Triage results delivered to Discord

### MCP Integrations

| MCP Server                | Network Policy                                | Purpose                       |
| ------------------------- | --------------------------------------------- | ----------------------------- |
| kubectl-mcp-server        | `allow-mcp-kubectl-egress` (kubectl-mcp:8000) | Kubernetes cluster operations |
| n8n                       | `allow-n8n-egress` (n8n-system:5678)          | Workflow automation           |
| mcp-victoriametrics       | `allow-mcp-vm-egress` (observability:8080)    | Metrics queries               |
| Context7                  | world egress                                  | Library documentation         |
| mcporter (Home Assistant) | world egress                                  | Home automation               |

### Skills

**Bundled skills** (enabled in config): github, gh-issues, healthcheck, mcporter, skill-creator, weather

**Custom skills** (installed from ClawHub via init-skills): mcp-hass, ontology, humanizer

**MCP-based skills** (enabled in config): mcp-context7, mcp-hass, mcp-n8n

### Memory and Sessions

| Feature               | Setting                                                                                                        |
| --------------------- | -------------------------------------------------------------------------------------------------------------- |
| Session scope         | per-sender                                                                                                     |
| Session idle reset    | 60 minutes                                                                                                     |
| Memory search         | Hybrid vector/text (OpenAI `text-embedding-3-small`)                                                           |
| Context tokens        | 1M (with `context1m` enabled on Sonnet 4.6 and Opus 4.6)                                                       |
| Context pruning       | cache-ttl mode, 3h TTL, keep last 3 assistant messages, soft-trim 0.3 / hard-clear 0.5                         |
| Compaction            | safeguard mode, 50% max history share, 24k reserve floor, memory flush at 40k tokens to `memory/YYYY-MM-DD.md` |
| Max concurrent agents | 4 (8 subagents)                                                                                                |
| Agent timeout         | 600 seconds                                                                                                    |

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n openclaw
flux get helmrelease -n flux-system openclaw

# Force reconcile
flux reconcile kustomization openclaw --with-source

# View logs
kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c main
kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c chromium

# Check init container logs
kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c init-workspace
kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c init-config
kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw -c init-skills

# Run doctor (diagnose and fix common issues)
kubectl exec -it -n openclaw deploy/openclaw -c main -- \
  node dist/index.js doctor --fix
```

### Claude Code Credentials

Claude Code authentication is managed via credentials stored in the `openclaw-workspace-config` SOPS secret. The `init-skills` container copies `.credentials.json` from the secret mount to `/home/node/.openclaw/.claude/.credentials.json` on the PVC.

To update credentials: edit the `.credentials.json` field in `openclaw-workspace-config.sops.yaml` and redeploy.

### Anthropic API Auth

OpenClaw supports two Anthropic auth modes (configured in `openclaw.json` under `auth.profiles`):

- **Subscription token** (`mode: "token"`): Uses Claude subscription auth. Generate with `claude setup-token` locally, then paste into the running pod.
- **API key** (`mode: "api_key"`): Add `ANTHROPIC_API_KEY` to `openclaw-secrets.sops.yaml`. OpenClaw auto-detects the env var.

The current config uses subscription token auth for Anthropic and API key auth for OpenAI.

### Adding ClawHub Skills

Skills are installed declaratively via the `init-skills` init container. Edit the skill list in `app/init-skills.sh`:

```bash
for skill in mcp-hass ontology humanizer; do
```

Skills are installed from [ClawHub](https://clawhub.com) on pod startup and persist on the PVC. Already-installed skills are skipped (idempotent).

### Runtime Tools

The `init-skills` init container installs runtime tools that skills depend on. These persist on the PVC and are made available to the main container via the `entrypoint.sh` wrapper (prepends custom paths to `$PATH`).

| Tool                   | Version Source                           | Purpose                                       |
| ---------------------- | ---------------------------------------- | --------------------------------------------- |
| Aikido safe-chain      | `SAFE_CHAIN_VERSION` in `init-skills.sh` | Supply chain security for npm/pip/uv installs |
| GitHub CLI (`gh`)      | `GH_VERSION` in `init-skills.sh`         | GitHub API access for skills                  |
| Go                     | `GO_VERSION` in `init-skills.sh`         | Go runtime for skills                         |
| Python (via uv)        | `UV_VERSION` in `init-skills.sh`         | Python runtime for skills                     |
| mcporter               | `MCPORTER_VERSION` in `init-skills.sh`   | MCP client for Home Assistant etc.            |
| Claude Code (`claude`) | Installed via `claude.ai/install.sh`     | Claude CLI for AI-assisted development        |

Versions are pinned with Renovate annotations for automated updates. Version marker files (`.versions/` on the PVC) track what's installed so Renovate bumps trigger reinstallation on the next pod restart. `GH_TOKEN` is injected from `openclaw-secrets.sops.yaml` for `gh` authentication.

### Workspace

The OpenClaw workspace lives in a dedicated git repository ([anthony-spruyt/openclaw-workspace](https://github.com/anthony-spruyt/openclaw-workspace)) and is synced on every pod startup by the `init-workspace` init container.

**How it works:**

1. `init-workspace` configures a single git credential dispatcher that routes tokens by repo path: whitelisted repos use `GIT_CODE_TOKEN` (read-write), all other GitHub repos use `GH_TOKEN` (read-only)
2. On first boot, clones the repo to `/home/node/.openclaw/workspace` on the PVC
3. On subsequent restarts, fast-forward pulls the latest changes
4. If pull fails (e.g. diverged history), force-syncs to `origin/main`
5. The `.gitconfig` is shared with the main container via `GIT_CONFIG_GLOBAL` so the agent can push changes back

**Environment variables** (in `openclaw-secrets.sops.yaml`):

| Variable             | Purpose                                                                     |
| -------------------- | --------------------------------------------------------------------------- |
| `GIT_WORKSPACE_REPO` | Clone URL (e.g. `https://github.com/anthony-spruyt/openclaw-workspace.git`) |
| `GIT_CODE_TOKEN`     | Fine-grained PAT with read-write access to whitelisted repos                |
| `GH_TOKEN`           | GitHub PAT for all other GitHub repos (e.g. `spruyt-labs` pulls)            |

Sensitive workspace config files (e.g. MCP credentials) are NOT stored in the workspace repo. Instead, they are mounted as read-only files from the SOPS-encrypted `openclaw-workspace-config` Secret (e.g. `mcporter.json` is mounted directly at `workspace/config/mcporter.json` via subPath).

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
   - Go to GitHub > Settings > SSH and GPG keys > New SSH key
   - Key type: **Signing Key**
   - Paste contents of `/tmp/openclaw-signing.pub`

4. Clean up local key files:

   ```bash
   rm /tmp/openclaw-signing /tmp/openclaw-signing.pub
   ```

**How it works:**

- The private key is staged at `/tmp/id_signing` (secret subPath mount) and copied to `/home/node/.openclaw/.ssh/id_signing` by `init-workspace`
- `init-workspace` writes a `.gitconfig` with `commit.gpgSign = true` and `gpg.format = ssh`
- At commit time, git calls `ssh-keygen -Y sign` using the installed key
- The commit author email (`99536297+anthony-spruyt@users.noreply.github.com`) matches the GitHub account where the signing key is registered

**Verifying signing works:**

```bash
kubectl exec -it -n openclaw deploy/openclaw -c main -- \
  git -C /home/node/.openclaw/workspace log --show-signature -1
```

Look for `Good "git" signature` in the output.

### Config Changes

OpenClaw config lives in `app/openclaw.json` (with JSON Schema validation via `openclaw-schema.json`). The init-config container handles config setup with two modes:

- **overwrite** (current default): Replaces PVC config with Helm-managed config on every restart
- **merge**: Deep-merges Helm config into existing PVC config (preserves runtime changes)

To switch modes, change `CONFIG_MODE` in `values.yaml` under the `init-config` container.

## SSO Authentication

SSO is implemented via Authentik's Proxy Provider with Traefik forward-auth.

### How It Works

1. User navigates to `https://openclaw.${EXTERNAL_DOMAIN}`
2. Traefik's forwardAuth middleware calls the Authentik outpost
3. Authentik authenticates user (must be in "OpenClaw Users" group)
4. Authenticated request is forwarded to OpenClaw gateway

### Post-Deployment Checklist

1. Verify the Authentik blueprint is applied: check for "OpenClaw SSO" in Authentik admin
2. Add your user to the "OpenClaw Users" group in Authentik
3. Verify the outpost is deployed: `kubectl get deploy -n openclaw -l app.kubernetes.io/managed-by=goauthentik.io`
4. Configure Claude credentials (see above)

### Configuration Files

| Component      | Location                                                      |
| -------------- | ------------------------------------------------------------- |
| Blueprint      | `authentik-system/authentik/app/blueprints/openclaw-sso.yaml` |
| Outpost RBAC   | `app/authentik-outpost-rbac.yaml`                             |
| Ingress Routes | `traefik/traefik/ingress/openclaw/`                           |

See [Authentik README](../../authentik-system/authentik/README.md#adding-sso-via-proxy-provider-forward-auth) for the complete SSO integration pattern.

## Troubleshooting

### Common Issues

1. **Pod stuck in Init**
   - **Symptom**: Pod never reaches Running state
   - **Diagnosis**: Check init container logs (`init-workspace`, `init-config`, or `init-skills`)
   - **Resolution**: `init-skills` requires outbound HTTPS for npm/ClawHub. Verify Cilium egress policy allows 443.

2. **Authentik outpost not deploying**
   - **Symptom**: No `ak-outpost-*` deployment in openclaw namespace
   - **Diagnosis**: Check Authentik server logs for RBAC errors
   - **Resolution**: Verify `authentik-outpost-rbac.yaml` is applied and the blueprint is loaded

3. **502 on first access**
   - **Symptom**: Browser shows 502 Bad Gateway
   - **Diagnosis**: Outpost may not be ready yet, or OpenClaw pod not running
   - **Resolution**: Wait for outpost deployment, check pod readiness

4. **Claude credentials expired**
   - **Symptom**: Agent responds with auth errors
   - **Resolution**: Update credentials in `openclaw-workspace-config.sops.yaml` or re-run `claude setup-token` and paste into pod

5. **Config changes not taking effect**
   - **Symptom**: Updated `openclaw.json` but behavior unchanged
   - **Diagnosis**: Current config mode is `overwrite` - changes should apply on next restart
   - **Resolution**: Reconcile the kustomization to trigger a restart, or delete the pod manually

6. **Workspace sync failed**
   - **Symptom**: `init-workspace` logs show clone/pull failure
   - **Diagnosis**: Check `GIT_WORKSPACE_REPO` and `GIT_CODE_TOKEN` in `openclaw-secrets`. Verify the token has repo access.
   - **Resolution**: The init container never fails the pod - a missing workspace is recoverable (OpenClaw bootstraps defaults). Fix the secret and restart.

7. **MCP server unreachable**
   - **Symptom**: Agent cannot reach kubectl-mcp, n8n, or VictoriaMetrics MCP
   - **Diagnosis**: Check Cilium network policies and target service health
   - **Resolution**: Verify the corresponding CNP exists and the target pod is running in its namespace

## File Reference

| Component               | Location                                                      |
| ----------------------- | ------------------------------------------------------------- |
| Namespace               | `namespace.yaml`                                              |
| Kustomization           | `openclaw/ks.yaml`                                            |
| HelmRelease             | `openclaw/app/release.yaml`                                   |
| Helm values             | `openclaw/app/values.yaml`                                    |
| OpenClaw config         | `openclaw/app/openclaw.json`                                  |
| Config JSON Schema      | `openclaw/app/openclaw-schema.json`                           |
| Init: workspace sync    | `openclaw/app/init-workspace.sh`                              |
| Init: config merge      | `openclaw/app/init-config.sh`                                 |
| Init: skill install     | `openclaw/app/init-skills.sh`                                 |
| Entrypoint wrapper      | `openclaw/app/entrypoint.sh`                                  |
| Secrets (SOPS)          | `openclaw/app/openclaw-secrets.sops.yaml`                     |
| Workspace config (SOPS) | `openclaw/app/openclaw-workspace-config.sops.yaml`            |
| PVC                     | `openclaw/app/persistent-volume-claim.yaml`                   |
| Network policies        | `openclaw/app/network-policies.yaml`                          |
| Outpost RBAC            | `openclaw/app/authentik-outpost-rbac.yaml`                    |
| Ingress routes          | `traefik/traefik/ingress/openclaw/`                           |
| Authentik blueprint     | `authentik-system/authentik/app/blueprints/openclaw-sso.yaml` |

## References

- [OpenClaw Documentation](https://docs.openclaw.ai/)
- [OpenClaw Gateway Config](https://docs.openclaw.ai/gateway/)
- [OpenClaw Providers](https://docs.openclaw.ai/providers/anthropic)
- [ClawHub Skills](https://clawhub.com)
- [Reference Helm Chart](https://github.com/serhanekicii/openclaw-helm)
