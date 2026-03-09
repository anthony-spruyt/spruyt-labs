# kyverno-policies - Cluster Policies

## Overview

Custom Kyverno policies for the spruyt-labs homelab. These policies automate resource management and enforce cluster standards.

## Prerequisites

- Kyverno installed and running (dependsOn: kyverno)

## Policies

### add-default-limitrange

Automatically generates a LimitRange in application namespaces to provide default resource requests for containers that don't specify them. This ensures all pods have at least Burstable QoS class.

**Behavior:**

- Triggers on namespace creation
- Creates a LimitRange with default CPU/memory requests
- Synchronized: updates/deletes when policy changes
- Applies to existing namespaces via `generateExisting: true`

**Default Requests Applied:**

| Resource | Default Request |
|----------|-----------------|
| CPU      | 10m             |
| Memory   | 64Mi            |

**Excluded Namespaces:**

Infrastructure and critical namespaces are excluded to avoid conflicts with their resource configurations:

- Kubernetes system: kube-system, kube-public, kube-node-lease
- GitOps/Policy: flux-system, kyverno
- Core infrastructure: cert-manager, cilium-secrets, cloudflare-system, external-dns, external-secrets, kubelet-csr-approver, reloader, spegel, traefik, velero
- Storage: csi-addons-system, rook-ceph
- Database operators: cnpg-system
- Observability: observability
- System utilities: chrony, irq-balance

### add-helmrelease-defaults

Injects default configuration into all HelmReleases that don't already specify them, using Kyverno's `+(anchor)` syntax for true "default if not set" semantics.

**Defaults Applied:**

| Field | Default Value |
|-------|---------------|
| `spec.timeout` | 10m |
| `spec.interval` | 4h |
| `spec.install.crds` | CreateReplace |
| `spec.install.strategy.name` | RetryOnFailure |
| `spec.rollback.cleanupOnFail` | true |
| `spec.rollback.recreate` | true |
| `spec.upgrade.cleanupOnFail` | true |
| `spec.upgrade.crds` | CreateReplace |
| `spec.upgrade.strategy.name` | RemediateOnFailure |
| `spec.upgrade.remediation.remediateLastFailure` | true |
| `spec.upgrade.remediation.retries` | 2 |

**Overriding Defaults:**

Set the field explicitly in the HelmRelease spec. For example, to use a 15m timeout:

```yaml
spec:
  timeout: 15m
```

## Operation

### Key Commands

```bash
# Check policy status
kubectl get clusterpolicy add-default-limitrange

# View generated LimitRanges
kubectl get limitrange -A -l app.kubernetes.io/managed-by=kyverno

# Check a specific namespace's LimitRange
kubectl get limitrange -n <namespace> default-limits -o yaml

# Force policy reconciliation
flux reconcile kustomization kyverno-policies --with-source
```

### Adding Namespace Exclusions

1. Edit `cluster/apps/kyverno/policies/app/default-limitrange.yaml`
2. Add namespace to the `exclude.any.resources.names` list
3. Commit and push
4. If policy update is rejected (immutable field error):

   ```bash
   kubectl delete clusterpolicy add-default-limitrange
   flux reconcile ks kyverno-policies --with-source
   ```

## Troubleshooting

### Common Issues

1. **Pod fails with "requests must be less than or equal to limit"**

   - **Cause**: App requests more memory than LimitRange default limit
   - **Resolution**: Either add explicit limits to the app, or exclude the namespace from the policy

2. **LimitRange not created in new namespace**

   - **Diagnosis**: Check if namespace is in exclude list or policy is ready
   - **Resolution**:

     ```bash
     kubectl get clusterpolicy add-default-limitrange -o jsonpath='{.status.conditions}'
     kubectl logs -n kyverno -l app.kubernetes.io/component=background-controller --tail=20
     ```

3. **Orphaned LimitRanges after policy changes**

   - **Cause**: Policy deleted without `synchronize: true`
   - **Resolution**: With `synchronize: true`, Kyverno auto-cleans generated resources

## References

- [Kyverno Generate Rules](https://kyverno.io/docs/writing-policies/generate/)
- [LimitRange Documentation](https://kubernetes.io/docs/concepts/policy/limit-range/)
