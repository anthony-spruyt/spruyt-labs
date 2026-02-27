# Cluster Validator Reference

Quick-lookup tables for validation. Consult during validation runs.

## Common Failure Patterns

| Error Pattern | Likely Cause | Quick Check | Common Fix |
|--------------|--------------|-------------|------------|
| `ImagePullBackOff` | Registry auth, wrong tag, private repo | `kubectl describe pod <pod>` | Check image tag, imagePullSecrets |
| `CrashLoopBackOff` | App crash, config error, missing deps | `kubectl logs <pod> --previous` | Check config, env vars, dependencies |
| `Pending` | No resources, node selector, affinity | `kubectl describe pod <pod>` | Check node resources, tolerations |
| `CreateContainerConfigError` | Missing configmap/secret | `kubectl describe pod <pod>` | Verify configmap/secret exists |
| `ErrImagePull` | Image doesn't exist | Check image name/tag | Fix image reference |
| HR `install retries exhausted` | Helm values error | `flux logs --kind=HelmRelease` | Check values against chart |
| KS `Source not found` | Missing HelmRepository/GitRepo | Check source references | Create or fix source |
| `connection refused` | Service not ready, wrong port | Check endpoints, service | Fix port, wait for ready |
| Network policy blocking | CNP denying traffic | `hubble observe -n <ns>` | Check egress/ingress rules |

## Resource-Specific Validation Matrix

| Resource Type | Health Indicators | Failure Signals | Key Commands |
|---------------|-------------------|-----------------|--------------|
| **Kustomization** | Ready=True, revision matches | Ready=False, suspended | `flux get ks <name>` |
| **HelmRelease** | Ready=True, chart version correct | install failed, upgrade failed | `flux get hr <name>` |
| **Deployment** | Available replicas = desired | Unavailable, progressing stuck | `kubectl rollout status` |
| **StatefulSet** | Ready replicas = desired | Pods not ordinal-ready | `kubectl get sts` |
| **Pod** | Running, all containers ready | CrashLoop, Pending, Error | `kubectl get pods -o wide` |
| **Service** | Endpoints populated | No endpoints | `kubectl get endpoints` |
| **IngressRoute** | Routes configured | Missing middleware, TLS errors | `kubectl get ingressroute` |
| **Certificate** | Ready=True, not expiring | Ready=False, renewal failed | `kubectl get cert` |
| **CronJob** | Test job completes, logs clean | Test job timeout, RBAC errors | `kubectl create job --from=cronjob/<name>` |
| **CiliumNetworkPolicy** | Applied, no denies in logs | Blocking traffic | `hubble observe` |

## Reconciliation Timeline

| Time | Expected State |
|------|----------------|
| 0-30s | Flux webhook triggered, source controller fetching |
| 30-60s | Kustomization reconciling, HelmRelease processing |
| 60-120s | Resources applied, pods starting |
| 120-180s | Pods running, health checks passing |
| 180-300s | Dependency chains settling |
| 300s+ | If not ready, likely a genuine issue |

## Change-Type Detection

| Change Type | Indicators | Focus On | Skip |
|-------------|------------|----------|------|
| `helm-release` | HelmRelease, values.yaml changed | HR status, pod health, app logs | Kustomization-only checks |
| `kustomization` | ks.yaml, kustomization.yaml | Kustomization status, resource creation | Helm-specific checks |
| `talos-config` | talos/, machine configs | Node health, system pods | Flux reconciliation |
| `network-policy` | CiliumNetworkPolicy, NetworkPolicy | Connectivity, policy status | Application logs |
| `namespace` | namespace.yaml only | Namespace exists, labels | Deep app validation |
| `infrastructure` | Storage, ingress, certs | System services, cluster-wide health | App-specific checks |
| `cronjob-workload` | HelmRelease where primary resource is CronJob | CronJob template, manual test job, pod logs | Deployment/StatefulSet rollout checks |
| `mixed` | Multiple types | ALL checks | Nothing |
