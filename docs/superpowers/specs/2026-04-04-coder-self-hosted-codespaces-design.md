# Coder: Self-Hosted Codespaces Platform

## Overview

Deploy [Coder](https://coder.com) on the homelab Kubernetes cluster to provide a browser-based VS Code development environment accessible from any device via the internet. Supports any repo's `.devcontainer/devcontainer.json` — not limited to a single project.

**Use case:** Develop from a phone or any browser while away from the desktop, with full toolchain access (kubectl, helm, flux, talosctl, Claude CLI, Docker, etc.).

**Access:** External via `code.${EXTERNAL_DOMAIN}` through Cloudflare Tunnel. No `lan-ip-whitelist` middleware — accessible from anywhere with Authentik OIDC authentication.

## Architecture

```text
Internet -> Cloudflare Tunnel -> Traefik -> code.${EXTERNAL_DOMAIN}
                                               |
                                          Coder (OIDC via Authentik)
                                               |
                                    +----------+----------+
                                    |                     |
                              Coder Control Plane    Workspace Pods
                              (Web UI, API,          (per-repo, built from
                               Provisioner)           devcontainer.json)
                                    |
                              CNPG PostgreSQL
```

### Components

| Component | Purpose | Location |
| --- | --- | --- |
| Coder Helm chart | Control plane (web UI, API, provisioner) | `cluster/apps/coder-system/coder/app/` |
| CNPG PostgreSQL | Coder's database with Barman S3 backups | `cluster/apps/coder-system/coder/app/` |
| Authentik blueprint | OIDC provider, application, group, policy | `cluster/apps/authentik-system/authentik/app/blueprints/coder-sso.yaml` |
| IngressRoute + Certificate | `code.${EXTERNAL_DOMAIN}` via Traefik | `cluster/apps/traefik/traefik/ingress/coder-system/` |
| SSH key rotation CronJob | Weekly rotation of workspace SSH signing key | `cluster/apps/coder-system/coder/app/` |
| GitHub App token | Git auth via existing `github-system` rotation infra | ExternalSecret from `github-system` |
| SOPS secrets | SSH key, tokens, OIDC creds | `cluster/apps/coder-system/coder/app/*-secrets.sops.yaml` |
| Coder Terraform template | Workspace pod definition | `coder/templates/devcontainer/` (manual `coder templates push`) |
| VPA | Recommendation-only for `coder` Deployment | `cluster/apps/coder-system/coder/app/vpa.yaml` |
| Network policies | CiliumNetworkPolicy resources | `cluster/apps/coder-system/coder/app/network-policies.yaml` |
| Namespace | PSA-labeled namespace | `cluster/apps/coder-system/namespace.yaml` |

### Namespace

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: coder-system
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
    descheduler.kubernetes.io/exclude: "true"
```

**Security note:** The `privileged` PSA enforce level is required because workspace pods run Docker-in-Docker, which needs elevated capabilities. This is scoped to the `coder-system` namespace only.

**Descheduler exclusion:** Workspace pods with active development sessions must not be evicted. Add `coder-system` to the per-plugin `namespaces.exclude` lists in `cluster/apps/kube-system/descheduler/app/values.yaml`.

### Flux Kustomization (ks.yaml)

Single Kustomization for the Coder app:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas-cjso.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app coder
  namespace: flux-system
spec:
  targetNamespace: coder-system
  path: ./cluster/apps/coder-system/coder/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: cnpg-operator
    - name: plugin-barman-cloud
    - name: external-secrets
    - name: authentik
  prune: true
  timeout: 5m
  wait: true
```

**Top-level registration:** Add `- ./coder-system` to `cluster/apps/kustomization.yaml` resources list so Flux discovers the namespace and ks.yaml.

**Ingress:** The ingress resources are not a separate Kustomization. Instead:

1. Add `coder-system/` subdirectory under `cluster/apps/traefik/traefik/ingress/`
2. Add `- ./coder-system` to `cluster/apps/traefik/traefik/ingress/kustomization.yaml` resources list
3. Add `- name: coder` to the existing `traefik-ingress` Kustomization's `dependsOn` list in `cluster/apps/traefik/traefik/ks.yaml`

## Authentication

Coder integrates with Authentik via **OIDC** (not forward-auth). Coder natively supports OIDC and handles its own login flow via redirect to Authentik.

### Authentik Blueprint

- **Type:** OAuth2 provider (same pattern as Grafana/Headlamp)
- **Flow:** `default-provider-authorization-implicit-consent`
- **Invalidation flow:** `default-provider-invalidation-flow`
- **Client type:** Confidential
- **Redirect URI:** `https://code.${EXTERNAL_DOMAIN}/api/v2/users/oidc/callback` (verify exact path from Coder docs during implementation — path may vary by version)
- **Scopes:** openid, profile, email
- **Signing key:** Research during implementation whether Coder requires RS256 (like Headlamp) or works with HS256 default
- **Group:** "Coder Users" with policy binding restricting access
- **No outpost needed** — Coder handles auth directly

The blueprint must be added to the `authentik-blueprints` ConfigMap's `files:` list in `cluster/apps/authentik-system/authentik/app/kustomization.yaml`.

### OIDC Credential Delivery

Follows the existing Grafana/Vaultwarden/Headlamp pattern:

1. **SOPS secret in `authentik-system`** — stores Coder OIDC client ID + secret as env vars consumed by the Authentik blueprint (`!Env CODER_OIDC_CLIENT_ID`, `!Env CODER_OIDC_CLIENT_SECRET`)
2. **ExternalSecret in `coder-system`** — copies the OIDC client credentials from the Authentik namespace secret using cross-namespace RBAC (Role + RoleBinding in `authentik-system`, like the existing `grafana-oauth-reader` pattern in `external-secrets-rbac.yaml`)
3. **Coder HelmRelease** — references the ExternalSecret-created secret for OIDC configuration

Add Coder to the `oauth-secret-rotation` CronJob for automated OIDC secret rotation. Also add `oauth-rotation-rbac.yaml` in the Coder app directory (Role + RoleBinding allowing the `oauth-secret-rotation` ServiceAccount from `authentik-system` to patch the Coder ExternalSecret for force-sync), following the Headlamp pattern.

### Traefik IngressRoute

Standard HTTPS route to Coder service with `compress` middleware. No forward-auth middleware — Coder manages its own authentication via OIDC.

## Storage

### PVCs (Ceph)

| PVC | Mount | Purpose |
| --- | --- | --- |
| CNPG-managed | PostgreSQL data dir | Coder control plane database |
| Per-workspace | `/workspaces` | Repo clones, uncommitted work survives restarts |
| Per-workspace | `/home/vscode` | VS Code extensions, Claude config/memory, shell history |

### CNPG PostgreSQL

Follows the Authentik CNPG pattern:

- CNPG Cluster resource with Barman cloud backup plugin
- S3 object store configuration for backups (same S3 bucket/prefix pattern)
- Scheduled backup CronJob
- Pooler resources (optional, can enable later under load)

### Kubernetes Secrets

| Secret | Contents | How Used |
| --- | --- | --- |
| `coder-ssh-signing-key` | Dedicated SSH signing-only key | Full volume mount at `/home/vscode/.ssh/` (not subPath, for auto-refresh) |
| `coder-talosconfig` | Talos client config | Mounted at `/home/vscode/.talos/config` |
| `coder-terraform-creds` | Terraform credentials | Mounted at `/home/vscode/.terraform.d/` |
| `coder-env-tokens` | API tokens (Claude, GitHub, etc.) | Injected as env vars |
| `coder-oidc` (in `authentik-system`) | Authentik OIDC client ID + secret | Consumed by blueprint, copied via ExternalSecret |
| `coder-ssh-rotation-token` | GitHub PAT with `admin:ssh_signing_key` scope | Used by SSH key rotation CronJob |

All secrets SOPS-encrypted in git.

**Mount strategy:** Secrets used by workspace pods are mounted as full volume mounts (not `subPath`) so that Kubernetes automatically propagates updates when Secrets change. Propagation delay is up to the kubelet sync period (typically ~1 minute).

## Credentials & Security

### Git Authentication (Clone/Push)

HTTPS with a short-lived **GitHub App installation token**, leveraging the existing `github-system/github-token-rotation` infrastructure:

1. The existing CronJob in `github-system` rotates GitHub App installation tokens every ~50 minutes
2. Coder workspaces consume the token via an **ExternalSecret** in `coder-system` that reads from `github-system`
3. Git credential helper in workspace reads the token on each operation
4. No pod restart needed — Secret volume auto-refreshes

**Integration with existing infrastructure:**

- Add `coder-system` as a consumer of the existing `github-token-rotation` CronJob
- Add an ExternalSecret in `coder-system` to copy the token from `github-system`
- Add a reader RoleBinding in `github-system` for the `coder-system` SecretStore ServiceAccount
- Add `coder-system` to the `force_sync_consumers` list in the existing CronJob
- If the Coder workspace needs different permissions (e.g., `contents: write` on additional repos), add those repos to the existing GitHub App installation or create a separate App managed by the same rotation CronJob

### Git Commit Signing

Dedicated SSH key used **only** for signing:

- Registered on GitHub as a **signing key** (not authentication key)
- Cannot clone, push, or authenticate — only sign commits
- If exfiltrated, attacker can sign commits but cannot access repos
- Mounted from Kubernetes Secret into workspace via full volume mount

### SSH Key Rotation

Weekly CronJob (same pattern as `oauth-secret-rotation` in Authentik namespace):

1. Generate new SSH key pair
2. Add new public key to GitHub account via API (`POST /user/ssh_signing_keys`)
3. Remove old public key from GitHub (`DELETE /user/ssh_signing_keys/{id}`)
4. Update Kubernetes Secret with new private key
5. Kubernetes auto-refreshes full volume mounts — no workspace restart needed (propagation delay ~1 minute)

Requires a GitHub PAT with `admin:ssh_signing_key` scope, stored in `coder-ssh-rotation-token` Secret.

### kubectl Access

- Workspace pods use a **ServiceAccount** with `cluster-admin` ClusterRoleBinding
- In-cluster config is automatic — no kubeconfig file needed
- kubectl CLI uses `/var/run/secrets/kubernetes.io/serviceaccount/token` transparently
- Can be restricted to a custom ClusterRole later

### Threat Model

Primary concern: compromise of Claude CLI or a malicious package inside the workspace.

| Credential | Blast Radius | Mitigation |
| --- | --- | --- |
| GitHub App token | 1 hour of repo access, scoped repos | Auto-expires, rotates hourly |
| SSH signing key | Can sign commits as user | Cannot access repos, revocable, rotates weekly |
| kubectl (SA) | Full cluster access via SA token (no additional auth beyond pod access) | Workspace access gated by Authentik OIDC; restrict SA to custom ClusterRole later |
| talosconfig | Talos API access | Workspace access gated by Authentik OIDC |
| Claude API key | API billing | Workspace access gated by Authentik OIDC |
| Terraform creds | Cloud access | Workspace access gated by Authentik OIDC |

**Note:** The ServiceAccount token provides direct Kubernetes API access without further authentication. The primary defense is preventing unauthorized workspace access via Authentik OIDC. A compromised process inside the workspace has full cluster-admin. This is acceptable for a single-user homelab but should be restricted for multi-user deployments.

## Docker-in-Docker

Required for MegaLinter and container builds in the qa-validator workflow.

**Approach:** The devcontainer `docker-in-docker` feature handles this — same as the local dev container. Coder builds from `devcontainer.json` via `devcontainer-cli`, which installs and starts Docker inside the workspace container.

The workspace pod needs elevated permissions for DinD. Research the minimum required capabilities during implementation — may work with `SYS_ADMIN` + `NET_ADMIN` instead of full `privileged: true`. The namespace PSA is set to `privileged` to allow either approach.

## Network Policies

CiliumNetworkPolicy resources covering:

| Policy | Direction | Purpose |
| --- | --- | --- |
| Traefik -> Coder control plane | Ingress | Web UI and API access |
| Coder -> CNPG | Egress | Database connectivity |
| Coder -> Authentik | Egress | OIDC token validation |
| Coder -> kube-api | Egress | Workspace pod management |
| Workspace pods -> kube-api | Egress | kubectl access (cluster-admin SA) |
| Workspace pods -> world | Egress | git clone, npm install, pip install, container image pulls |
| Workspace pods -> Talos API | Egress | talosctl access |
| Prometheus -> Coder | Ingress | Metrics scraping |
| CNPG internal | Ingress/Egress | Cluster replication, operator, backup |

Exact ports and selectors determined during implementation.

## Devcontainer Compatibility

The same `devcontainer.json` works in both environments with no changes:

| Concern | Local (Docker Desktop) | Coder (Kubernetes) |
| --- | --- | --- |
| User | `vscode` | `vscode` (from base image) |
| Home dir | `/home/vscode` | `/home/vscode` |
| Docker | `docker-in-docker` feature | Same feature, elevated pod permissions |
| SSH agent | Host agent socket mounted | No agent; key file mounted directly |
| Env vars | `--env-file ~/.secrets/.env` | Kubernetes Secret as env vars |
| Tools | `setup-devcontainer.sh` | Same script runs via `postCreateCommand` |
| Claude CLI | Installed in `post-create.sh` | Same |
| VS Code extensions | Microsoft marketplace | Open VSX (code-server) |

`runArgs` and `mounts` from `devcontainer.json` are ignored by Coder (they're Docker-specific). Coder handles equivalent functionality via the Terraform template.

## Coder Terraform Template

Stored at `coder/templates/devcontainer/` in the repo root. This directory is **outside Flux's reconciliation scope** — template changes are applied manually via `coder templates push` from a workspace or local dev container. A CI pipeline could automate this in the future.

Template defines:

- **Input parameter:** Git repo URL (user selects when creating workspace)
- **Pod spec:** Elevated permissions for DinD (privileged or specific caps), ServiceAccount with cluster-admin, resource requests/limits
- **PVCs:** Two persistent volumes for `/workspaces` and `/home/vscode` on Ceph storage class
- **Secret mounts:** SSH signing key (full volume), talosconfig, terraform creds
- **Env vars:** From `coder-env-tokens` Secret
- **Devcontainer integration:** Coder's native devcontainer support auto-detects and builds from `.devcontainer/devcontainer.json`

## VPA

Recommendation-only VPA targeting the `coder` Deployment from the Helm chart. Workspace pods are user-managed and ephemeral — VPA is not applied to workspace pods.

## Scaling

- Deploy with `replicas: 1` for the Coder control plane
- User manually scales workspace pods as needed (create/stop workspaces via Coder UI)
- No auto-scaling — single-user homelab

## Open Questions

1. Exact pod security capabilities needed for DinD (privileged vs specific caps) — research during implementation
2. Whether Coder OIDC requires RS256 signing key or works with HS256 default — research during implementation
3. Coder Helm chart version and specific values — check upstream during implementation
