# Coder - Self-Hosted Dev Workspaces

## Overview

Browser and SSH dev workspaces for humans and AI coding agents, provisioned as Kata-isolated pods in `coder-workspaces`. Login is Authentik OIDC. Templates are pushed from Git by [coder-template-sync](../coder-template-sync/README.md); workspace-side secrets, RBAC and policies live in `cluster/apps/coder-workspaces/`.

## Operations

### Release channel: stable only

Coder ships two channels from the same Helm repository. Mainline is cut from `main` on the first Tuesday of each month; stable is the previous mainline, promoted after roughly a month in the field.

Both are published as plain semver chart versions, and every GitHub release carries `prerelease=false`, so no Renovate `versioning` or `ignoreUnstable` setting can tell them apart — a newer mainline chart simply looks like an available upgrade.

This deployment tracks **stable only**. Expect the pinned chart version to sit roughly one minor behind the newest version visible in the Helm repository; that gap is intentional, not a missed upgrade.

The mechanism lives in the shared Renovate config at [repo-operator](https://github.com/anthony-spruyt/repo-operator/tree/main/.github/renovate), which this repository extends:

- A `coder-stable` custom datasource reads `https://api.github.com/repos/coder/coder/releases/latest`. Coder's own `install.sh` resolves its `--stable` flag by following that same redirect, which makes the GitHub "latest release" marker the authoritative stable pointer.
- The `flux` manager is disabled for this chart, so the Helm repository index no longer proposes mainline.
- A `# renovate:` annotation above `version:` in `release.yaml` binds the pin to that datasource.

### Server image tag

`coder.image.tag` is deliberately left empty in `values.yaml`. The chart falls back to `v{{ .Chart.AppVersion }}`, which always equals the pinned chart version, so the server and chart stay in lockstep on one tracked version.

A pinned tag here would drift: Renovate's `helm-values` manager does not recognise Coder's `image.repo` / `image.tag` shape, so it never saw the key, and every chart bump left the image behind until someone edited it by hand.

This is the one image-bearing `values.yaml` in the repository without a `@sha256:` digest — a consequence of the same blind spot, since Renovate cannot maintain a digest it cannot see.

### Workspace isolation model

Workspace containers run `privileged: true` (envbuilder/kaniko and rootful podman need it) inside a Kata VM, which is the real isolation boundary (#933). Because of that:

- `coder-workspaces` is labelled PSA `privileged`; PSA there is a guardrail, not the control.
- The Kyverno policy `restrict-privileged-to-coder-workspace-sa` (in `coder-workspaces/coder-workspaces/app/`) only admits privileged pods whose ServiceAccount starts with `coder-workspace`.
- Templates pin `runtime_class_name = "kata"` and a `kata.spruyt-labs/ready=true` node selector. Removing either from a template removes the VM boundary.

Rotated Secrets reach running workspaces within a couple of minutes: the Kata agent copies Secret and ConfigMap volume updates into the VM (limit 16 files / 1 MiB per volume). `subPath` mounts never update, so mount rotating Secrets as whole volumes (#3189).

### What each template gets

| Template       | ServiceAccount                           | Credentials beyond the shared set                                                   |
| -------------- | ---------------------------------------- | ----------------------------------------------------------------------------------- |
| `spruyt-labs`  | `coder-workspace-ops` (cluster-wide ops) | Talos `os:operator` config, Terraform credentials, SOPS age key, project env        |
| `devcontainer` | `coder-workspace` (no API access)        | none                                                                                |
| `xfg`          | `coder-workspace` (no API access)        | `coder-workspace-env-xfg` (Azure DevOps and GitLab tokens, reach any repo it opens) |

The shared set, in every template: `coder-workspace-env-common`, the `spruyt-labs-bot` SSH key and write-tier GitHub App token, Nexus pull auth, and Claude managed settings. Project env Secrets come after common in `env_from`, so their keys override common ones with the same name.

Every workspace commits and runs `gh` as `spruyt-labs-bot`, the same identity as the write-tier Claude agents. In repos that require PR approval, the owner approves its PRs with their own account.

`coder-workspace-ops` is a scoped-down cluster-admin (no Secrets, no RBAC/webhook/CRD writes); its ClusterRole is in `coder-workspaces/coder-workspaces/app/rbac.yaml`. The SOPS age key is pulled from `flux-system` by an ExternalSecret, so a `spruyt-labs` workspace can decrypt every SOPS file in the repo.

The spruyt-labs Talos config comes from the Talos `ServiceAccount` `coder-workspace-talos` (role `os:operator`, short-lived and auto-renewed), not a static admin config (#3188).

The three `main.tf` files are near-copies: beyond this table they differ only in the `repo` default and, for `spruyt-labs`, parameter order, a higher memory request, and the startup steps that build the kubeconfig, link the Terraform credentials and wrap `talosctl`. A fix to shared behaviour must be applied to all three.

### Nexus routing

All templates route podman pulls and the envbuilder layer cache through [Nexus](../../nexus-system/nexus/README.md), authenticated with `coder-workspace-nexus-clients`. envbuilder ignores registry mirrors: the only mirror setting it reads, `KANIKO_REGISTRY_MIRROR`, never reaches kaniko's pull code (envbuilder skips the kaniko CLI that turns it into a registry map). So the base image only comes
from Nexus if the Dockerfile opts in with `FROM ${BASE_REGISTRY}/...`, fed by `build.args.BASE_REGISTRY: ${localEnv:BASE_REGISTRY:ghcr.io}`; the templates set `BASE_REGISTRY` to Nexus `docker-group`, with no ghcr.io fallback (#3229). Repo-operator ships this in its synced `.devcontainer/`. Revisit when [coder/envbuilder#511](https://github.com/coder/envbuilder/pull/511) (`KANIKO_REGISTRY_MAP`)
ships. The layer cache is keyed on the repo (`envbuilder-cache/<owner>/<repo>`), so a new workspace reuses layers from earlier builds of the same repo. The endpoints and the reasons behind them are commented inline in each `main.tf`.

Apt only goes through Nexus if the workspace repo opts in: `devcontainer.json` passes `build.args.NEXUS_URL: ${localEnv:NEXUS_URL}` and the Dockerfile rewrites `sources.list` to `apt-ubuntu-proxy` (#988; see this repo's `.devcontainer/`). Devcontainer features that add their own apt sources (github-cli, nodesource, hashicorp, PPAs) still fetch upstream directly.

### Database credentials

The `coder` Postgres login is ESO-generated (`sl_` prefix) into `coder-cnpg-owner` by `app/cnpg-roles-eso.yaml`; nothing is in SOPS and superuser access is off. `bootstrap.initdb.secret` points CNPG at it, so CNPG no longer generates `coder-cnpg-cluster-app`.

`CODER_PG_CONNECTION_URL` interpolates `CODER_PG_PASSWORD`. Keep the `CODER_` prefix: provisionerd strips `CODER_*` variables from Terraform's environment, but not `PG*` ones.

The database is deliberately not a db-mcp source: it holds OAuth tokens, agent tokens and user secrets that a read-only role could still pull into an agent's context. Use `kubectl cnpg psql coder-cnpg-cluster -n coder-system`.

To rotate, delete both the Secret and the ExternalSecret (`kubectl -n coder-system delete secret,externalsecret coder-cnpg-owner`). Flux recreates the ExternalSecret with a new password and CNPG applies it. Then `kubectl -n coder-system rollout restart deploy/coder` - Reloader ignores a recreated Secret. Running workspaces are not affected.

## Troubleshooting

1. **Workspace pod stuck Pending**

   - **Cause**: No worker labelled `kata.spruyt-labs/ready=true` has capacity. The label comes from `talos/patches/worker/08-configure-node-labels.yaml`.
   - **Fix**: Free capacity on a labelled worker, or check the Kata runtime class in `kube-system/kata-runtimeclass`.

2. **Workspace pod rejected: "Privileged pods in coder-workspaces require a 'coder-workspace\*' ServiceAccount"**

   - **Cause**: A template set a ServiceAccount outside the `coder-workspace*` prefix.
   - **Fix**: Use `coder-workspace` or `coder-workspace-ops`.

## References

- [Coder Documentation](https://coder.com/docs)
- [Coder Helm Chart](https://github.com/coder/coder/tree/main/helm)
