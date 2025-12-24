# Cluster Maintenance Guide

Regular maintenance procedures for the Talos Linux Kubernetes cluster.

## Pre-Change Verification

Complete these verification steps before submitting changes to ensure cluster stability.

### Kubernetes Manifest Changes

1. Confirm resource type exists:

   ```bash
   kubectl api-resources
   ```

2. Review fields you intend to modify:

   ```bash
   kubectl explain <resource_type>[.<field_path>] --recursive
   ```

3. Archive current manifest:

   ```bash
   kubectl get <resource_type> <resource_name> -n <namespace> -o yaml
   ```

4. Validate Helm chart defaults or CRD documentation through upstream references
5. Capture assumptions, dependencies, and version requirements in change notes

### Terraform Infrastructure Changes

1. Format and validate:

   ```bash
   terraform fmt
   terraform validate
   ```

2. Run plan and capture output:

   ```bash
   terraform plan -out plan.tfplan
   ```

3. Request review with plan output attached
4. Apply with exact plan reviewed:

   ```bash
   terraform apply plan.tfplan
   ```

5. Confirm state file synchronization and monitor for drift

### Talos Configuration Changes

1. Assess cluster health before changes:

   ```bash
   talosctl health
   talosctl logs -f kubelet
   ```

2. Diff intended vs live config:

   ```bash
   talosctl config diff
   ```

3. Apply changes:

   ```bash
   talosctl apply-config --insecure --nodes <target> --file <config.yaml>
   ```

4. Verify post-change status:

   ```bash
   talosctl health
   kubectl get nodes
   ```

## Day-2 Operations

- Scale Talos workloads safely using the graceful shutdown pattern in [talos/README.md](../talos/README.md)
- Launch privileged pods for node diagnostics: `task dev-env:priv-pod node=<node>`

## Renovate Dependency Management

Renovate automates dependency updates. See [docs/rules/renovate.md](rules/renovate.md) for details.

### Quarterly Maintenance

1. Review all Renovate configuration files in `.github/renovate/`
2. Monitor update success rates and system stability
3. Audit manager coverage for all dependency types

### Troubleshooting Updates

| Issue            | Solution                                               |
| ---------------- | ------------------------------------------------------ |
| Failed updates   | Review PR comments; adjust stabilityDays or groupings  |
| Missing deps     | Audit manager configurations and file patterns         |
| Stability issues | Roll back by reverting commits; increase stabilityDays |
| Config errors    | Validate JSON5 syntax; test with Renovate dry-run      |

## Certificate Renewal

Certificates are managed by cert-manager and auto-renew. To check status:

```bash
kubectl get certificates -A
kubectl describe certificate <name> -n <namespace>
```

## Storage Maintenance

### Ceph Health

```bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd status
```

### Before Node Maintenance

```bash
# Set noout flag before taking node offline
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd set noout

# After node returns
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd unset noout
```

## Quarterly Resource Review

Run this prompt with Claude Code every quarter to review and optimize resource allocation:

---

Review and optimize Kubernetes resource requests and limits for all workloads. Follow this procedure:

1. **Query current throttling status (24h)**:

   ```bash
   kubectl -n dev-debug run vmquery-throttle --image=curlimages/curl --restart=Never --rm -i -- \
     curl -s 'http://vmsingle-victoria-metrics-k8s-stack.observability:8428/api/v1/query' \
     --data-urlencode 'query=topk(30,sum by (namespace,pod,container)(rate(container_cpu_cfs_throttled_periods_total[24h])) / sum by (namespace,pod,container)(rate(container_cpu_cfs_periods_total[24h]))*100)' | \
     jq -r '.data.result[] | select(.metric.container) | "\(.metric.namespace)/\(.metric.pod)/\(.metric.container): \(.value[1] | tonumber | floor)%"' | sort -t: -k2 -rn
   ```

2. **Query P99 CPU usage (7d)**:

   ```bash
   kubectl -n dev-debug run vmquery-cpu --image=curlimages/curl --restart=Never --rm -i -- \
     curl -s 'http://vmsingle-victoria-metrics-k8s-stack.observability:8428/api/v1/query' \
     --data-urlencode 'query=quantile_over_time(0.99,sum by (namespace,container)(rate(container_cpu_usage_seconds_total[5m]))[7d])*1000' | \
     jq -r '.data.result[] | "\(.metric.namespace)/\(.metric.container): \(.value[1] | tonumber | floor)m p99"' | sort -t: -k2 -rn | head -50
   ```

3. **Query P99 memory usage (7d)**:

   ```bash
   kubectl -n dev-debug run vmquery-mem --image=curlimages/curl --restart=Never --rm -i -- \
     curl -s 'http://vmsingle-victoria-metrics-k8s-stack.observability:8428/api/v1/query' \
     --data-urlencode 'query=max(quantile_over_time(0.99,container_memory_working_set_bytes[7d]))by(namespace,container)/1024/1024' | \
     jq -r '.data.result[] | "\(.metric.namespace)/\(.metric.container): \(.value[1] | tonumber | floor)Mi p99"' | sort -t: -k2 -rn | head -50
   ```

4. **Discover ALL workloads with resource configurations**:

   ```bash
   # Find all values.yaml files that define resources
   find cluster/apps -name "values.yaml" -exec grep -l "resources:" {} \; | sort

   # Find all HelmRelease files (may have postRenderer patches with resources)
   find cluster/apps -name "release.yaml" -exec grep -l "resources:" {} \; | sort

   # List all running pods to cross-reference with metrics
   kubectl get pods -A --no-headers | awk '{print $1"/"$2}' | sort
   ```

   **Important**: Read EVERY values.yaml file found above to review current resource settings. Do not skip any workloads. Compare each workload's current settings against the P99 metrics from steps 2-3.

5. **Apply these sizing rules**:
   - **Requests**: P99 usage + 20% buffer
   - **CPU Limits**:
     - Critical infra (Flux, Authentik, Rook-Ceph, Traefik): Remove CPU limits entirely
     - Non-critical: 3-5x requests
   - **Memory Limits**: 1.5-2x requests (memory causes OOMKill, be generous)

6. **Workload criticality tiers**:
   - **Tier 1 (no CPU limit)**: Flux controllers, Authentik, CNPG, Rook-Ceph, Traefik, Cilium
   - **Tier 2 (generous limits)**: VictoriaMetrics, N8N, Vaultwarden, Velero
   - **Tier 3 (normal limits)**: Headlamp, RedisInsight, Whoami, Chrony

7. **Update values.yaml files** for any workloads where:
   - Throttle % > 5% (needs limit increase or removal)
   - Requests < 80% of P99 usage (under-provisioned)
   - Requests > 200% of P99 usage (over-provisioned, wasting scheduler capacity)

8. **Validate changes** after push:
   - Wait 30 minutes for metrics to stabilize
   - Re-run throttle query to confirm < 5% throttling
   - Check no pods are pending due to insufficient resources

## Related

- [docs/disaster-recovery.md](disaster-recovery.md) - DR procedures
- [docs/rules/](rules/) - Operational rules
- [talos/README.md](../talos/README.md) - Talos-specific procedures
