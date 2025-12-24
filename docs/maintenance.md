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

Review and optimize Kubernetes resource requests and limits for all workloads.

---

### Step 1: Run Metrics Queries

First, clean up any leftover query pods:

```bash
kubectl -n dev-debug delete pod -l app.kubernetes.io/purpose=metrics-query --ignore-not-found 2>/dev/null || true
```

Run all three queries using `--command` flag for reliability (run in parallel):

**Throttling (24h)**:

```bash
kubectl -n dev-debug run vmquery-throttle --labels=app.kubernetes.io/purpose=metrics-query \
  --image=curlimages/curl --restart=Never --rm -i --command -- \
  curl -s 'http://vmsingle-victoria-metrics-k8s-stack.observability:8428/api/v1/query' \
  --data-urlencode 'query=topk(30,sum by (namespace,pod,container)(rate(container_cpu_cfs_throttled_periods_total[24h])) / sum by (namespace,pod,container)(rate(container_cpu_cfs_periods_total[24h]))*100)'
```

**P99 CPU (7d)**:

```bash
kubectl -n dev-debug run vmquery-cpu --labels=app.kubernetes.io/purpose=metrics-query \
  --image=curlimages/curl --restart=Never --rm -i --command -- \
  curl -s 'http://vmsingle-victoria-metrics-k8s-stack.observability:8428/api/v1/query' \
  --data-urlencode 'query=quantile_over_time(0.99,sum by (namespace,container)(rate(container_cpu_usage_seconds_total[5m]))[7d])*1000'
```

**P99 Memory (7d)**:

```bash
kubectl -n dev-debug run vmquery-mem --labels=app.kubernetes.io/purpose=metrics-query \
  --image=curlimages/curl --restart=Never --rm -i --command -- \
  curl -s 'http://vmsingle-victoria-metrics-k8s-stack.observability:8428/api/v1/query' \
  --data-urlencode 'query=max(quantile_over_time(0.99,container_memory_working_set_bytes[7d]))by(namespace,container)/1024/1024'
```

Parse JSON results locally - filter to containers with throttle >5% and create a comparison table.

### Step 2: Map Containers to Config Files

For each throttled container, locate its resource config:

```bash
find cluster/apps -name "values.yaml" -exec grep -l "resources:" {} \; | sort
find cluster/apps -name "release.yaml" -exec grep -l "resources:" {} \; | sort
```

Common container-to-file mappings:

| Container              | Config File                                                        |
| ---------------------- | ------------------------------------------------------------------ |
| sso-config             | cluster/apps/rook-ceph/rook-ceph-cluster/app/release.yaml          |
| reloader               | cluster/apps/reloader/reloader/app/values.yaml                     |
| redisinsight/app       | cluster/apps/redisinsight/redisinsight/app/values.yaml             |
| whoami                 | cluster/apps/whoami/whoami/app/values.yaml                         |
| chrony                 | cluster/apps/chrony/chrony/app/values.yaml                         |
| headlamp               | cluster/apps/headlamp-system/headlamp/app/values.yaml              |
| technitium             | cluster/apps/technitium/technitium/app/values.yaml                 |
| technitium (secondary) | cluster/apps/technitium/technitium-secondary/app/values.yaml       |
| cilium-agent           | cluster/apps/kube-system/cilium/app/values.yaml                    |
| mon/mgr/osd            | cluster/apps/rook-ceph/rook-ceph-cluster/app/values.yaml           |
| registry (spegel)      | cluster/apps/spegel/spegel/app/values.yaml                         |
| _most others_          | cluster/apps/\<namespace\>/\<app\>/app/values.yaml                 |

### Step 3: Decision Matrix

| Condition                      | Action                                         |
| ------------------------------ | ---------------------------------------------- |
| Throttle >5% AND Tier 1        | Remove CPU limit                               |
| Throttle >5% AND Tier 2/3      | Increase limit to 10x requests OR remove       |
| P99 CPU > requests             | Increase requests to P99 + 20%                 |
| P99 CPU < 50% of requests      | Reduce requests (but min 5m)                   |
| Throttle >50% with no limit    | Increase requests (bursty workload)            |

**Tier Definitions**:

- **Tier 1 (no CPU limit)**: flux-\*, authentik-\*, cnpg-\*, rook-ceph-\*, traefik, cilium-\*, reloader, chrony, external-dns, cert-manager, technitium-\*, spegel, kyverno
- **Tier 2 (generous limits 5-10x)**: victoria-metrics-\*, n8n-\*, vaultwarden, velero
- **Tier 3 (normal limits 3-5x)**: headlamp, redisinsight, whoami, minecraft, foundryvtt

### Step 4: Validate After Push

Wait 30 minutes for metrics to stabilize, then:

```bash
# Re-run throttle query - all containers should be <5%
# Check no pods pending
kubectl get pods -A | grep -i pending

# Check recent OOMKills
kubectl get events -A --field-selector reason=OOMKilled --sort-by='.lastTimestamp' | tail -10
```

### Step 5: Update This Documentation

After completing the review, update this procedure if any issues were found:

- **Container mappings**: Add any new containers to the table in Step 2 if they weren't listed
- **Tier definitions**: Update tier lists if apps were added/removed or reclassified
- **Decision matrix**: Refine thresholds or actions if the current guidance proved incorrect
- **Query improvements**: Update queries if they needed modification to work correctly
- **Missing steps**: Add any steps that were needed but not documented

Commit documentation updates separately from resource changes with message:
`docs(maintenance): update resource review procedure`

## Related

- [docs/disaster-recovery.md](disaster-recovery.md) - DR procedures
- [docs/rules/](rules/) - Operational rules
- [talos/README.md](../talos/README.md) - Talos-specific procedures
