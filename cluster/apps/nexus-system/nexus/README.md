# Nexus OSS - Artifact Proxy for Workspaces and Agents

## Overview

Pull-through cache for apt, container images, npm, PyPI and NuGet, plus the envbuilder/kaniko layer cache, so Coder workspace builds, agent pre-commit runs and dev PCs don't hit upstream registries each time (#968). Nexus serves plain HTTP in-cluster; Traefik terminates TLS for LAN access at `nexus.lan.${EXTERNAL_DOMAIN}` (UI, apt, npm, PyPI, NuGet) and `nexus-docker.lan.${EXTERNAL_DOMAIN}`
(docker-group).

> **Scope:** Only workspaces, agents and dev PCs use Nexus. Cluster image pulls (kubelet, Spegel, Flux OCIRepositories) stay on direct upstream paths — Nexus being down must never block bootstrap or Flux reconciliation.

## Prerequisites

SOPS secrets in `app/`, created by hand:

| Secret                 | Keys                               | Used by                                                |
| ---------------------- | ---------------------------------- | ------------------------------------------------------ |
| `nexus-admin`          | `admin-username`, `admin-password` | bootstrap sidecar, provisioning Job                    |
| `nexus-upstream-creds` | Docker Hub and GHCR username/token | proxy repos (avoids anonymous rate limits)             |
| `nexus-secrets-key`    | `secrets.json`                     | Nexus secret encryption key (`NEXUS_SECRETS_KEY_FILE`) |

### Client users

Docker client passwords are ESO-generated (`sl_` prefix) into `nexus-clients` by `app/clients-eso.yaml`, one key per user:

| User               | Role                                       | Used by                                                  |
| ------------------ | ------------------------------------------ | -------------------------------------------------------- |
| `workspace-puller` | `nx-anonymous` (read-only)                 | podman in workspaces (`auth.json`)                       |
| `envbuilder-cache` | `nx-anonymous` + `envbuilder-cache-writer` | envbuilder/kaniko (layer-cache pulls and pushes)         |
| `local-dev`        | `nx-anonymous` (read-only)                 | podman in local devcontainers (`~/.secrets/.env.common`) |

`coder-workspaces/coder-workspaces/app/nexus-clients-eso.yaml` reads `nexus-clients` through a SecretStore and templates the two workspace client configs into `coder-workspace-nexus-clients`. `local-dev` is copied by hand into each host's `~/.secrets/.env.common` as `NEXUS_DOCKER_PASSWORD` (see `DEVELOPMENT.md`). Never delete `nexus-clients` itself: every user would get a new password at once.

## Operations

### Connectors

| Port   | Repo               | Purpose                                                                      |
| ------ | ------------------ | ---------------------------------------------------------------------------- |
| `8081` | all non-docker     | UI, REST API, apt, npm, PyPI and NuGet proxies, metrics                      |
| `8082` | `docker-group`     | OCI v2 at host root; aggregates Docker Hub, GHCR, Quay, MCR, registry.k8s.io |
| `8083` | `envbuilder-cache` | Hosted docker repo for the kaniko layer cache                                |

Docker connectors serve at the host root with no `/repository/` prefix. `docker-group` uses `forceBasicAuth`, so anonymous pulls get a 401 after the bearer realm is advertised — clients must log in as one of the client users above. Every client uses Nexus as a mirror, so a 401 or an outage falls back to the upstream registry instead of failing the pull.

### NuGet sources must use the HTTPS host

`nuget-proxy` (nuget.org v3) is consumed as `https://nexus.lan.${EXTERNAL_DOMAIN}/repository/nuget-proxy/index.json`, set in a user-level NuGet config by the Coder workspace template and the devcontainer setup, never in a committed `nuget.config`. Nexus builds the URLs inside `index.json` from the request (Traefik's `X-Forwarded-Proto`), so through Traefik they are `https://`; .NET 9+ rejects
plain-HTTP sources with `NU1302`. The in-cluster address (`http://nexus.nexus-system.svc:8081`) advertises `http://` URLs and fails that check, so in-cluster .NET clients need the HTTPS host or `allowInsecureConnections`. GitHub-hosted CI restores from nuget.org directly.

### First boot: admin bootstrap

The official image ignores `NEXUS_SECURITY_INITIAL_PASSWORD`. On an empty PVC, Nexus writes a random password to `/nexus-data/admin.password`; the `bootstrap` sidecar (`app/bootstrap.sh`) uses it to create the admin user from `nexus-admin`, disable the built-in `admin`, delete the password file, and re-encrypt stored secrets to the `primary` key from `nexus-secrets-key`. Marker files on the PVC
(`.bootstrap-done`, `.rekey-primary-done`) make later restarts a no-op.

Consequence: the user in `nexus-admin` is **not** `admin`, and changing `nexus-admin` after first boot does not change the live password.

### Provisioning Job

`nexus-provision-repos` (`app/provision.sh`) upserts every repo, the cleanup policy and tasks (see [Cleanup](#cleanup)), the `anonymous-extras` role (`nx-metrics-all`, `nx-healthcheck-read`, so vmagent can scrape anonymously), the `envbuilder-cache-writer` role and the client users. It is GET-merge-PUT safe and re-runs whenever `provision.sh` changes (hashed ConfigMap +
`kustomize.toolkit.fluxcd.io/force: "Enabled"`). It also resets each client user's password from `nexus-clients` on every run.

### Cleanup

The provisioner owns cleanup; do not configure it in the UI, the next run overwrites it.

- Cleanup policy `unused-90d` (all formats, not downloaded in 90 days) is attached to every repo except `docker-group`. It goes through `/service/rest/internal/cleanup-policies`, because the public cleanup API is Pro-only (404 on Community).
- The built-in "Cleanup service" task (daily 01:00) only soft-deletes. `docker-gc-all` (Sundays 02:00) soft-deletes untagged Docker layers and manifests older than 30 days, including digest-pinned proxy pulls, and `compact-default` (daily 04:00) frees the disk. Task times are UTC.
- Proxy content that gets deleted is fetched again on the next pull; envbuilder layers are rebuilt on the next build.

To re-run without a script change, delete the Job and reconcile the `nexus` Kustomization.

### Admin password rotation

1. Change the password via the API (`PUT /service/rest/v1/security/users/<admin-username>/change-password`).
2. Update `admin-password` in `nexus-admin`.

In that order: the provisioning Job reads `admin-password` on every run and 401s if it is stale.

### Rotating a client user password

1. `kubectl -n nexus-system delete externalsecret nexus-client-<user>` (`workspace-puller`, `envbuilder-cache` or `local-dev`). Flux recreates it and ESO writes a new key into `nexus-clients`; the other users' keys are untouched.
2. Re-run the provisioning Job (see [Cleanup](#cleanup)) so Nexus gets the new password.
3. Workspace users: `coder-workspace-nexus-clients` follows within 5 minutes. Running workspaces keep the old auth until restarted: templates mount `auth.json` with `subPath` and read the envbuilder config at pod start.
4. `local-dev`: update `NEXUS_DOCKER_PASSWORD` in each host's `~/.secrets/.env.common`, then rebuild its devcontainers.

## Troubleshooting

1. **Provisioning Job fails on a single `upsert`**

   - **Cause**: Usually Nexus not yet writable (the Job retries, `backoffLimit: 10`), or the repo JSON no longer matches the Nexus API version.
   - **Fix**: Check the provisioner logs; for privilege-ID errors (`nx-metrics-all` renamed between versions) list `/v1/security/privileges?type=application` and adjust `provision.sh`.

2. **apt proxy returns 502/504**

   - **Cause**: Nexus auto-blocks a proxy repo after repeated upstream failures.
   - **Fix**: Unblock `apt-ubuntu-proxy` (or the affected repo) in the UI, or wait for the auto-unblock window.

3. **`java.net.BindException: Address already in use`**

   - **Cause**: Two repos claim the same `httpPort`.
   - **Fix**: Only `docker-group` (8082) and `envbuilder-cache` (8083) may set one in `provision.sh`.

4. **Pulls bypass Nexus, or envbuilder cache pushes fail with 401**

   - **Cause**: Nexus has not been given the current `nexus-clients` password (the Job has not run since it changed), or the workspace started before it changed. A local devcontainer with no `NEXUS_DOCKER_PASSWORD` shows up as anonymous 401s in the Nexus request log. Podman treats Nexus as a mirror, so a 401 silently falls back to the upstream registry (visible as upstream rate limits, not
     errors).
   - **Fix**: Re-run the provisioning Job, then restart the workspace. For local devcontainers, set `NEXUS_DOCKER_PASSWORD` in the host's `~/.secrets/.env.common` and rebuild.

## References

- [Sonatype Nexus Repository 3 documentation](https://help.sonatype.com/en/sonatype-nexus-repository.html)
- [Docker reverse-proxy strategies](https://help.sonatype.com/en/docker-repository-reverse-proxy-strategies.html)
