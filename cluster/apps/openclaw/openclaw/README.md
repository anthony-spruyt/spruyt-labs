# OpenClaw - AI Agent Platform

## Overview

OpenClaw is a self-hosted AI agent platform providing a web gateway for interacting with Claude models. It includes a Chromium sidecar for browser automation and supports extensible skills via ClawHub.

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
                                                   Chromium sidecar (:9222, localhost only)
```

### Security Model

| Layer | Control |
|-------|---------|
| Network | Cilium CNP: Traefik ingress on 18789, n8n MCP egress on 5678, world egress all ports |
| Auth | Authentik proxy provider with group-based access (OpenClaw Users) |
| DNS | Split DNS - LAN-only, no Cloudflare tunnel exposure |
| Container | read-only root filesystem, non-root (UID 1000), all caps dropped, seccomp RuntimeDefault |
| Namespace | PSA restricted (enforce + audit + warn) |

No application-layer auth is configured on OpenClaw itself. Cilium's trusted-proxy auth requires exact IP matching which is incompatible with Cilium's socket-level load balancing (dynamic pod IPs). The network + Authentik layers provide equivalent security.

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

### Claude Subscription Token Setup

OpenClaw uses Claude's subscription-based auth (setup-token) instead of an API key. This avoids per-token API billing but requires an interactive setup step after deployment.

**Initial setup:**

```bash
# 1. Generate token on your local machine (requires Claude CLI)
claude setup-token

# 2. Copy the token output, then paste it into the running pod
kubectl exec -it -n openclaw deploy/openclaw -c main -- \
  node dist/index.js models auth paste-token --provider anthropic
```

The token is stored on the PVC at `/home/node/.openclaw` and persists across pod restarts.

**Token renewal** (when expired):

```bash
# Same process - generate locally, paste into pod
claude setup-token
kubectl exec -it -n openclaw deploy/openclaw -c main -- \
  node dist/index.js models auth paste-token --provider anthropic
```

**Switching to API key** (alternative):

If you prefer usage-based billing with prompt caching support, add `ANTHROPIC_API_KEY` to `openclaw-secrets.sops.yaml` and redeploy. No config changes needed - OpenClaw auto-detects the env var.

### Adding ClawHub Skills

Skills are installed declaratively via the `init-skills` init container. Edit the skill list in `app/init-skills.sh`:

```bash
for skill in mcp-hass ontology humanizer; do
```

Skills are installed from [ClawHub](https://clawhub.com) on pod startup and persist on the PVC. Already-installed skills are skipped (idempotent).

### Runtime Tools

The `init-skills` init container also installs runtime tools that skills may depend on. These persist on the PVC and are made available to the main container via the `entrypoint.sh` wrapper (prepends custom paths to `$PATH`).

| Tool | Version Source | Purpose |
|------|---------------|---------|
| Aikido safe-chain | `SAFE_CHAIN_VERSION` in `init-skills.sh` | Supply chain security for npm/pip/uv installs |
| GitHub CLI (`gh`) | `GH_VERSION` in `init-skills.sh` | GitHub API access for skills |
| Go | `GO_VERSION` in `init-skills.sh` | Go runtime for skills |
| Python (via uv) | `UV_VERSION` in `init-skills.sh` | Python runtime for skills |
| mcporter | `MCPORTER_VERSION` in `init-skills.sh` | MCP client for Home Assistant etc. |
| Claude Code (`claude`) | Installed via `claude.ai/install.sh` | Claude CLI for AI-assisted development |

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

| Variable | Purpose |
|----------|---------|
| `GIT_WORKSPACE_REPO` | Clone URL (e.g. `https://github.com/anthony-spruyt/openclaw-workspace.git`) |
| `GIT_CODE_TOKEN` | Fine-grained PAT with read-write access to whitelisted repos |
| `GH_TOKEN` | GitHub PAT for all other GitHub repos (e.g. `spruyt-labs` pulls) |

Sensitive workspace config files (e.g. MCP credentials) are NOT stored in the workspace repo. Instead, they are mounted as read-only files from the SOPS-encrypted `openclaw-workspace-config` Secret (e.g. `mcporter.json` is mounted directly at `workspace/config/mcporter.json` via subPath).

### Config Changes

OpenClaw config lives in `app/openclaw.json` (with JSON Schema validation via `openclaw-schema.json`). The init-config container merges Helm-provided config with any existing config on the PVC (preserving runtime changes like installed skills).

To force a full config overwrite instead of merge:

```yaml
env:
  CONFIG_MODE: "overwrite"  # default is "merge"
```

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
4. Configure the Claude setup-token (see above)

### Configuration Files

| Component | Location |
|-----------|----------|
| Blueprint | `authentik-system/authentik/app/blueprints/openclaw-sso.yaml` |
| Outpost RBAC | `app/authentik-outpost-rbac.yaml` |
| Ingress Routes | `traefik/traefik/ingress/openclaw/` |

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

4. **Claude token expired**
   - **Symptom**: Agent responds with auth errors
   - **Resolution**: Re-run `claude setup-token` locally and paste into pod (see setup instructions above)

5. **Config changes not taking effect**
   - **Symptom**: Updated `openclaw.json` but behavior unchanged
   - **Diagnosis**: Merge mode preserves existing keys
   - **Resolution**: Either set `CONFIG_MODE: "overwrite"` or delete the PVC config and restart

6. **Workspace sync failed**
   - **Symptom**: `init-workspace` logs show clone/pull failure
   - **Diagnosis**: Check `GIT_WORKSPACE_REPO` and `GIT_CODE_TOKEN` in `openclaw-secrets`. Verify the token has repo access.
   - **Resolution**: The init container never fails the pod - a missing workspace is recoverable (OpenClaw bootstraps defaults). Fix the secret and restart.

## File Reference

| Component | Location |
|-----------|----------|
| Namespace | `namespace.yaml` |
| Kustomization | `openclaw/ks.yaml` |
| HelmRelease | `openclaw/app/release.yaml` |
| Helm values | `openclaw/app/values.yaml` |
| OpenClaw config | `openclaw/app/openclaw.json` |
| Config JSON Schema | `openclaw/app/openclaw-schema.json` |
| Init: workspace sync | `openclaw/app/init-workspace.sh` |
| Init: config merge | `openclaw/app/init-config.sh` |
| Init: skill install | `openclaw/app/init-skills.sh` |
| Entrypoint wrapper | `openclaw/app/entrypoint.sh` |
| Secrets (SOPS) | `openclaw/app/openclaw-secrets.sops.yaml` |
| Workspace config (SOPS) | `openclaw/app/openclaw-workspace-config.sops.yaml` |
| PVC | `openclaw/app/persistent-volume-claim.yaml` |
| Network policies | `openclaw/app/network-policies.yaml` |
| Outpost RBAC | `openclaw/app/authentik-outpost-rbac.yaml` |
| Ingress routes | `traefik/traefik/ingress/openclaw/` |
| Authentik blueprint | `authentik-system/authentik/app/blueprints/openclaw-sso.yaml` |

## References

- [OpenClaw Documentation](https://docs.openclaw.ai/)
- [OpenClaw Gateway Config](https://docs.openclaw.ai/gateway/)
- [OpenClaw Providers](https://docs.openclaw.ai/providers/anthropic)
- [ClawHub Skills](https://clawhub.com)
- [Reference Helm Chart](https://github.com/serhanekicii/openclaw-helm)
