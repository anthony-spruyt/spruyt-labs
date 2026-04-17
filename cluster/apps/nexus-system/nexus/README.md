# Nexus OSS - Artifact Proxy for Coder Workspace Builds

## Overview

Sonatype Nexus Repository 3 OSS deployed in-cluster via the `bjw-s-labs/app-template` chart as an apt + docker artifact proxy for Coder workspace (envbuilder) builds and developer workstations. Also hosts the kaniko layer cache on LAN-local Ceph storage, replacing the previous ghcr-hosted cache.

Runs as a single-replica StatefulSet with a 100Gi Ceph RBD PVC at `/nexus-data`. The Service exposes three ports:

- `8081` - UI, apt repositories, REST API, metrics
- `8082` - `docker-group` connector (OCI v2 at host-root for proxy pulls)
- `8083` - `envbuilder-cache` connector (hosted docker repo for kaniko layer cache)

Nexus listens plain HTTP only. Workspace pods hit `nexus.nexus-system.svc.cluster.local` with `ENVBUILDER_INSECURE=true`. Traefik terminates TLS (ZeroSSL) for dev PC access at `nexus.lan.${EXTERNAL_DOMAIN}` and `nexus-docker.lan.${EXTERNAL_DOMAIN}`.

> **Scope:** Explicitly for Coder workspace builds and developer workstations. Cluster image pulls (kubelet, Spegel, Flux OCIRepositories) remain on direct upstream paths — Nexus being down must never block cluster bootstrap or Flux reconciliation.
>
> **Note**: HelmRelease resources are created in the target namespace specified by ks.yaml `targetNamespace` (`nexus-system`).

## Prerequisites

- Kubernetes cluster with Flux CD
- `cert-manager` (ZeroSSL ClusterIssuer)
- `kyverno` (admission policies)
- `rook-ceph-cluster-storage` (provides `rook-ceph-block` StorageClass)
- SOPS secrets created by user:
  - `nexus-admin` (admin-username, admin-password)
  - `nexus-upstream-creds` (dockerhub-username/token, ghcr-username/token)

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n nexus-system
flux get helmrelease -n nexus-system nexus

# Force reconcile (GitOps approach)
flux reconcile kustomization nexus --with-source

# View logs
kubectl logs -n nexus-system -l app.kubernetes.io/name=nexus

# Provisioning Job status
kubectl get job -n nexus-system nexus-provision-repos
kubectl logs -n nexus-system -l app.kubernetes.io/name=nexus-provisioner

# List repositories via API (anonymous read granted)
curl https://nexus.lan.${EXTERNAL_DOMAIN}/service/rest/v1/repositories

# Anonymous metrics
curl https://nexus.lan.${EXTERNAL_DOMAIN}/service/metrics/prometheus
```

### UI Login

Access `https://nexus.lan.${EXTERNAL_DOMAIN}` (LAN IP whitelist enforced by Traefik middleware). Log in with `admin` and the password from the `nexus-admin` SOPS secret.

### Rerunning the Provisioning Job

The provisioner uses `configMapGenerator` for `provision.sh` — editing the script changes its hash, which Flux picks up. Because the Job manifest carries `kustomize.toolkit.fluxcd.io/force: "Enabled"`, Flux deletes and recreates the Job on every spec change. The Job is GET-merge-PUT safe — existing repos are updated in place, and anonymous-role privileges are merged (not replaced).

To force a rerun without a spec change:

```bash
kubectl delete job -n nexus-system nexus-provision-repos
flux reconcile kustomization nexus --with-source
```

### PVC Expansion

Online resize via Ceph RBD:

```bash
kubectl patch pvc data-nexus-0 -n nexus-system \
  -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'
```

### Admin Password Rotation

`NEXUS_SECURITY_INITIAL_PASSWORD` applies only on first-boot with an empty PVC. To rotate later:

1. `PUT /service/rest/v1/security/users/admin/change-password` via the API
2. Update the `nexus-admin` SOPS secret with the new password

The provisioning Job reads `admin-password` on every run — if it's stale, the Job's curl commands will 401. Always rotate in the API first, then update the secret.

## Troubleshooting

### Common Issues

1. **Provisioning Job stuck or CrashLoopBackOff**
   - **Symptom**: Repos never appear in the UI; `kubectl get job` shows 0/1 completions
   - **Diagnosis**: `kubectl logs -n nexus-system -l app.kubernetes.io/name=nexus-provisioner`
   - **Resolution**: Most common cause is Nexus not yet writable. Job retries up to `backoffLimit: 10`. If a specific `upsert` call 400s, check the repo JSON body against the Nexus API version. Privilege ID mismatch (`nx-metrics-all` vs `nx-metrics-read`) on older Nexus versions — grep `/v1/security/privileges?type=application` for the current ID and adjust `provision.sh`.

2. **apt upstream proxy returns 502/504**
   - **Symptom**: `curl https://nexus.lan.${EXTERNAL_DOMAIN}/repository/apt-ubuntu-proxy/dists/jammy/Release` fails
   - **Diagnosis**: Nexus auto-blocks proxy repos after upstream failures (configurable). Check Nexus UI → Repositories → `apt-ubuntu-proxy` → Status.
   - **Resolution**: Click "Unblock now" in UI, or wait for the auto-unblock window. Verify egress CNP rule permits `world:443/80`.

3. **Metrics endpoint unreachable from vmagent**
   - **Symptom**: VMPodScrape target shows as down in VictoriaMetrics
   - **Diagnosis**: `kubectl get vmpodscrape -n nexus-system nexus -o yaml`; check vmagent logs
   - **Resolution**: Confirm the CNP allows `k8s:app.kubernetes.io/name: vmagent` from `observability` to port 8081, and that `nx-metrics-all` is on the anonymous role (merged by the provisioning Job).

4. **Docker connector `BindException` in Nexus logs**
   - **Symptom**: Nexus log reports `java.net.BindException: Address already in use`
   - **Diagnosis**: Two repos claim the same `httpPort` in their JSON
   - **Resolution**: Fix `provision.sh` — `docker-group` owns `8082`, `envbuilder-cache` owns `8083`, no other repo should claim those.

## Maintenance

### Updates

```bash
# Update Nexus image via Renovate-managed digest pin in values.yaml,
# then Flux picks up the change:
flux reconcile kustomization nexus --with-source

# Check update status
kubectl get helmreleases -n nexus-system
```

## References

- [Spec: 2026-04-17-nexus-oss-coder-proxy-design.md](../../../../docs/superpowers/specs/2026-04-17-nexus-oss-coder-proxy-design.md)
- [Issue #968](https://github.com/anthony-spruyt/spruyt-labs/issues/968)
- [Sonatype Nexus Repository 3 documentation](https://help.sonatype.com/en/sonatype-nexus-repository.html)
- [Docker reverse-proxy strategies](https://help.sonatype.com/en/docker-repository-reverse-proxy-strategies.html)
- [bjw-s-labs app-template](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/other/app-template)
