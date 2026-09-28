# Nexus OSS - Artifact Proxy for Workspaces and Agents

## Overview

Pull-through cache for apt, container images, npm and PyPI, plus the envbuilder/kaniko layer cache, so Coder workspace builds, agent pre-commit runs and dev PCs don't hit upstream registries each time (#968). Nexus serves plain HTTP in-cluster; Traefik terminates TLS for LAN access at `nexus.lan.${EXTERNAL_DOMAIN}` (UI, apt, npm, PyPI) and `nexus-docker.lan.${EXTERNAL_DOMAIN}` (docker-group).

> **Scope:** Only workspaces, agents and dev PCs use Nexus. Cluster image pulls (kubelet, Spegel, Flux OCIRepositories) stay on direct upstream paths — Nexus being down must never block bootstrap or Flux reconciliation.

## Prerequisites

SOPS secrets in `app/`, created by hand:

| Secret                    | Keys                               | Used by                                                |
| ------------------------- | ---------------------------------- | ------------------------------------------------------ |
| `nexus-admin`             | `admin-username`, `admin-password` | bootstrap sidecar, provisioning Job                    |
| `nexus-upstream-creds`    | Docker Hub and GHCR username/token | proxy repos (avoids anonymous rate limits)             |
| `nexus-secrets-key`       | `secrets.json`                     | Nexus secret encryption key (`NEXUS_SECRETS_KEY_FILE`) |
| `nexus-workspace-clients` | `puller-password`                  | `workspace-puller` user                                |

`coder-workspaces/coder-workspaces/app/coder-workspace-nexus-clients.sops.yaml` holds the matching client-side auth for workspaces and must be updated whenever `puller-password` changes.

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

`nexus-provision-repos` (`app/provision.sh`) upserts every repo, the `anonymous-extras` role (`nx-metrics-all`, `nx-healthcheck-read`, so vmagent can scrape anonymously), and the `workspace-puller` user. It is GET-merge-PUT safe and re-runs whenever `provision.sh` changes (hashed ConfigMap + `kustomize.toolkit.fluxcd.io/force: "Enabled"`). It also resets `workspace-puller`'s password to
`puller-password` on every run.

To re-run without a script change, delete the Job and reconcile the `nexus` Kustomization.

### Admin password rotation

1. Change the password via the API (`PUT /service/rest/v1/security/users/<admin-username>/change-password`).
2. Update `admin-password` in `nexus-admin`.

In that order: the provisioning Job reads `admin-password` on every run and 401s if it is stale.

### Rotating the workspace puller password

Update `puller-password` in `nexus-workspace-clients` and the auth in `coder-workspace-nexus-clients` together. The provisioning Job applies the new password on its next run, so change `provision.sh` or re-run the Job. Running workspaces keep the old auth until restarted (Kata freezes secret mounts).

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

4. **Workspace image pulls fail with 401 from `:8082`**

   - **Cause**: `coder-workspace-nexus-clients` and `puller-password` are out of step.
   - **Fix**: Re-align them and re-run the provisioning Job.

## References

- [Sonatype Nexus Repository 3 documentation](https://help.sonatype.com/en/sonatype-nexus-repository.html)
- [Docker reverse-proxy strategies](https://help.sonatype.com/en/docker-repository-reverse-proxy-strategies.html)
