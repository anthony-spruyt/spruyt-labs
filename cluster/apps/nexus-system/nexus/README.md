# Nexus OSS - Artifact Proxy for Workspaces and Agents

## Overview

Pull-through cache for apt, container images, npm and PyPI, plus the envbuilder/kaniko layer cache, so Coder workspace builds, agent pre-commit runs and dev PCs don't hit upstream registries each time (#968). Nexus serves plain HTTP in-cluster; Traefik terminates TLS for LAN access at `nexus.lan.${EXTERNAL_DOMAIN}` (UI, apt, npm, PyPI) and `nexus-docker.lan.${EXTERNAL_DOMAIN}` (docker-group).

> **Scope:** Only workspaces, agents and dev PCs use Nexus. Cluster image pulls (kubelet, Spegel, Flux OCIRepositories) stay on direct upstream paths — Nexus being down must never block bootstrap or Flux reconciliation.

## Prerequisites

SOPS secrets in `app/`, created by hand:

| Secret                 | Keys                               | Used by                                                |
| ---------------------- | ---------------------------------- | ------------------------------------------------------ |
| `nexus-admin`          | `admin-username`, `admin-password` | bootstrap sidecar, provisioning Job                    |
| `nexus-upstream-creds` | Docker Hub and GHCR username/token | proxy repos (avoids anonymous rate limits)             |
| `nexus-secrets-key`    | `secrets.json`                     | Nexus secret encryption key (`NEXUS_SECRETS_KEY_FILE`) |

### Workspace users

Workspace passwords are ESO-generated (`sl_` prefix) into `nexus-clients` by `app/clients-eso.yaml`, one key per user:

| User               | Role                                       | Used by                                        |
| ------------------ | ------------------------------------------ | ---------------------------------------------- |
| `workspace-puller` | `nx-anonymous` (read-only)                 | podman in workspaces (`auth.json`)             |
| `envbuilder-cache` | `nx-anonymous` + `envbuilder-cache-writer` | envbuilder/kaniko (pulls + layer-cache pushes) |

`coder-workspaces/coder-workspaces/app/nexus-clients-eso.yaml` reads `nexus-clients` through a SecretStore and templates both client configs into `coder-workspace-nexus-clients`. Never delete `nexus-clients` itself: both users would get new passwords at once.

## Operations

### Connectors

| Port   | Repo               | Purpose                                                                      |
| ------ | ------------------ | ---------------------------------------------------------------------------- |
| `8081` | all non-docker     | UI, REST API, apt/npm/PyPI proxies, metrics                                  |
| `8082` | `docker-group`     | OCI v2 at host root; aggregates Docker Hub, GHCR, Quay, MCR, registry.k8s.io |
| `8083` | `envbuilder-cache` | Hosted docker repo for the kaniko layer cache                                |

Docker connectors serve at the host root with no `/repository/` prefix. `docker-group` uses `forceBasicAuth`, so anonymous pulls get a 401 after the bearer realm is advertised — clients must use `workspace-puller` (or admin).

### First boot: admin bootstrap

The official image ignores `NEXUS_SECURITY_INITIAL_PASSWORD`. On an empty PVC, Nexus writes a random password to `/nexus-data/admin.password`; the `bootstrap` sidecar (`app/bootstrap.sh`) uses it to create the admin user from `nexus-admin`, disable the built-in `admin`, delete the password file, and re-encrypt stored secrets to the `primary` key from `nexus-secrets-key`. Marker files on the PVC
(`.bootstrap-done`, `.rekey-primary-done`) make later restarts a no-op.

Consequence: the user in `nexus-admin` is **not** `admin`, and changing `nexus-admin` after first boot does not change the live password.

### Provisioning Job

`nexus-provision-repos` (`app/provision.sh`) upserts every repo, the cleanup policy and tasks (see [Cleanup](#cleanup)), the `anonymous-extras` role (`nx-metrics-all`, `nx-healthcheck-read`, so vmagent can scrape anonymously), the `envbuilder-cache-writer` role and the workspace users. It is GET-merge-PUT safe and re-runs whenever `provision.sh` changes (hashed ConfigMap +
`kustomize.toolkit.fluxcd.io/force: "Enabled"`). It also resets each workspace user's password from `nexus-clients` on every run.

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

### Rotating a workspace user password

1. `kubectl -n nexus-system delete externalsecret nexus-client-<user>` (`workspace-puller` or `envbuilder-cache`). Flux recreates it and ESO writes a new key into `nexus-clients`; the other user's key is untouched.
2. Re-run the provisioning Job (see [Cleanup](#cleanup)) so Nexus gets the new password.
3. `coder-workspace-nexus-clients` follows within 5 minutes. Running workspaces keep the old auth until restarted: templates mount `auth.json` with `subPath` and read the envbuilder config at pod start.

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

4. **Workspace pulls bypass Nexus, or envbuilder cache pushes fail with 401**

   - **Cause**: Nexus has not been given the current `nexus-clients` password (the Job has not run since it changed), or the workspace started before it changed. Podman treats Nexus as a mirror, so a 401 silently falls back to the upstream registry (visible as upstream rate limits, not errors).
   - **Fix**: Re-run the provisioning Job, then restart the workspace.

## References

- [Sonatype Nexus Repository 3 documentation](https://help.sonatype.com/en/sonatype-nexus-repository.html)
- [Docker reverse-proxy strategies](https://help.sonatype.com/en/docker-repository-reverse-proxy-strategies.html)
