# Quarterly Resource Review

Review and optimize Kubernetes resource requests and limits for all workloads.

Run this prompt every quarter to ensure resource allocation matches actual usage.

**Important:** This prompt automatically adjusts under-provisioned resources but only **flags** over-provisioned ones. Over-provisioning changes require explicit user approval.

---

## Step 1: Build Workload Inventory and Run Metrics Queries

First, clean up any leftover query pods from previous runs:

```bash
kubectl -n dev-debug delete pod -l app.kubernetes.io/purpose=metrics-query --ignore-not-found 2>/dev/null || true
```

### Step 1a: Get Authoritative Container List

Get a complete list of all containers running in the cluster (excludes Talos/Kubernetes-managed pods):

> **Note**: Copy commands exactly as written. The go-template uses `{{"\t"}}` and `{{"\n"}}` (single backslash) for tab/newline. Double-escaping (`{{"\\t"}}`) will break the output.

```bash
kubectl get pods -A -o go-template='{{range .items}}{{$ns := .metadata.namespace}}{{$pod := .metadata.name}}{{range .spec.containers}}{{$ns}}{{"\t"}}{{$pod}}{{"\t"}}{{.name}}{{"\n"}}{{end}}{{end}}' | grep -vE "^kube-system\s+(coredns|kube-apiserver|kube-controller-manager|kube-scheduler|kube-proxy)" | sort -u > /tmp/cluster-containers.txt && wc -l /tmp/cluster-containers.txt
# Expected: ~150-250 containers (varies with replica counts and maintenance jobs)
```

This provides the baseline to verify metrics queries return data for ALL workloads.

**Included**: All GitOps-managed apps including cilium, snapshot-controller (kube-system), flux-operator, flux-instance (flux-system).
**Excluded**: Only Talos-managed pods (coredns, kube-apiserver, kube-controller-manager, kube-scheduler, kube-proxy).

**Note**: The Container Count metrics query will show more containers than this inventory because it includes historical data from old replicasets and deleted pods. The important check is that every container in the live inventory appears in the metrics.

### Step 1b: Run Metrics Queries

Run all queries using `--command` flag for reliability:

**Throttling (24h)** - All containers, no limit:

```bash
kubectl -n dev-debug run vmquery-throttle --labels=app.kubernetes.io/purpose=metrics-query --image=curlimages/curl --restart=Never --rm -i --command -- curl -s 'http://vmsingle-victoria-metrics-k8s-stack.observability:8428/api/v1/query' --data-urlencode 'query=sum by (namespace,pod,container)(rate(container_cpu_cfs_throttled_periods_total[24h])) / sum by (namespace,pod,container)(rate(container_cpu_cfs_periods_total[24h]))*100'
```

**Container Count** - Completeness check (compare against Step 1a inventory):

```bash
kubectl -n dev-debug run vmquery-count --labels=app.kubernetes.io/purpose=metrics-query --image=curlimages/curl --restart=Never --rm -i --command -- curl -s 'http://vmsingle-victoria-metrics-k8s-stack.observability:8428/api/v1/query' --data-urlencode 'query=count(sum by (namespace,container)(rate(container_cpu_usage_seconds_total[5m])))'
```

**P99 CPU (7d)**:

```bash
kubectl -n dev-debug run vmquery-cpu --labels=app.kubernetes.io/purpose=metrics-query --image=curlimages/curl --restart=Never --rm -i --command -- curl -s 'http://vmsingle-victoria-metrics-k8s-stack.observability:8428/api/v1/query' --data-urlencode 'query=quantile_over_time(0.99,sum by (namespace,container)(rate(container_cpu_usage_seconds_total[5m]))[7d])*1000'
```

**P99 CPU (24h)** - For new workloads without 7 days of data:

```bash
kubectl -n dev-debug run vmquery-cpu-24h --labels=app.kubernetes.io/purpose=metrics-query --image=curlimages/curl --restart=Never --rm -i --command -- curl -s 'http://vmsingle-victoria-metrics-k8s-stack.observability:8428/api/v1/query' --data-urlencode 'query=quantile_over_time(0.99,sum by (namespace,container)(rate(container_cpu_usage_seconds_total[5m]))[24h])*1000'
```

**P99 Memory (7d)**:

```bash
kubectl -n dev-debug run vmquery-mem --labels=app.kubernetes.io/purpose=metrics-query --image=curlimages/curl --restart=Never --rm -i --command -- curl -s 'http://vmsingle-victoria-metrics-k8s-stack.observability:8428/api/v1/query' --data-urlencode 'query=max(quantile_over_time(0.99,container_memory_working_set_bytes[7d]))by(namespace,container)/1024/1024'
```

### Step 1c: Over-Provisioning Check

Find workloads requesting much more CPU than they use (ratio < 0.3 = over-provisioned):

```bash
kubectl -n dev-debug run vmquery-overprov --labels=app.kubernetes.io/purpose=metrics-query --image=curlimages/curl --restart=Never --rm -i --command -- curl -s 'http://vmsingle-victoria-metrics-k8s-stack.observability:8428/api/v1/query' --data-urlencode 'query=(sum by (namespace,container)(rate(container_cpu_usage_seconds_total[24h])) * 1000) / on(namespace,container) (sum by (namespace,container)(kube_pod_container_resource_requests{resource="cpu"} * 1000))'
```

### Step 1d: Analyze Results

Parse JSON results locally and create a comparison table:

1. **Verify completeness**: Container count from query should match Step 1a inventory
2. **Filter throttled**: Containers with throttle >5%
3. **Flag over-provisioned (REPORT ONLY)**: Containers with usage/request ratio <0.3
   - **DO NOT** reduce resources automatically
   - Present findings to user and wait for explicit approval before any changes
4. **Check for missing workloads**: Compare 7d vs 24h results - use 24h data for new workloads

---

## Step 2: Map Containers to Config Files

### Step 2a: Find All Workload Definitions

Locate ALL workload types (not just those with existing resources):

```bash
# All HelmRelease-based workloads
find cluster/apps -type f -name "*.yaml" \
  | xargs grep -l "kind: HelmRelease" | sort

# Direct manifests (Deployments, StatefulSets, DaemonSets, CronJobs)
find cluster/apps -type f -name "*.yaml" \
  | xargs grep -l "kind: Deployment\|kind: StatefulSet\|kind: DaemonSet\|kind: CronJob" | sort

# Database resources (CNPg clusters - often missed!)
find cluster/apps -name "*-cnpg-cluster.yaml" | sort
```

### Step 2b: Find Resource Configurations

```bash
# Files WITH explicit resources (currently configured)
find cluster/apps -name "values.yaml" -exec grep -l "resources:" {} \; | sort
find cluster/apps -name "*-cnpg-cluster.yaml" -exec grep -l "resources:" {} \; | sort

# Files WITHOUT explicit resources (priority review - need to add resources!)
for f in $(find cluster/apps -name "values.yaml"); do
  grep -q "resources:" "$f" || echo "MISSING: $f"
done
```

### Step 2c: Container-to-File Mappings

Use namespace from container name to locate config. Common patterns:

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
| snapshot-controller    | cluster/apps/kube-system/snapshot-controller/app/values.yaml       |
| flux-operator          | cluster/apps/flux-system/flux-operator/app/values.yaml             |
| flux-instance          | cluster/apps/flux-system/flux-instance/app/values.yaml             |
| mon/mgr/osd            | cluster/apps/rook-ceph/rook-ceph-cluster/app/values.yaml           |
| registry (spegel)      | cluster/apps/spegel/spegel/app/values.yaml                         |
| CNPg databases         | cluster/apps/\<namespace\>/\<app\>/app/\*-cnpg-cluster.yaml        |
| _most others_          | cluster/apps/\<namespace\>/\<app\>/app/values.yaml                 |

---

## Step 3: Decision Matrix

| Condition                                    | Action                                        |
| -------------------------------------------- | --------------------------------------------- |
| Throttle >5% AND critical-infrastructure     | Remove CPU limit (should already have none)   |
| Throttle >5% AND high-priority               | Increase limit (target 3-5x request)          |
| Throttle >5% AND standard/low/best-effort    | Increase limit per tier policy                |
| P99 CPU > requests                           | Increase requests to P99 + 20%                |
| P99 CPU < 30% of requests                    | **FLAG ONLY** - report to user, do not action |
| Throttle >50% with no limit                  | Increase requests (bursty workload)           |
| No explicit resources defined                | Add resources based on P99 metrics            |
| Missing from 7d query                        | Use 24h query data for new workloads          |
| Container count mismatch                     | Investigate missing workloads in Step 1a      |

### Over-Provisioning Changes (User Confirmation Required)

Over-provisioned workloads (usage/request ratio <0.3) are **flagged but NOT actioned automatically**.

**Workflow:**

1. Present flagged over-provisioned workloads to user with metrics
2. Wait for explicit user confirmation for each workload
3. Only reduce resources when user explicitly approves

**Rationale:** Over-provisioning is often intentional for burst capacity, future growth, or stability. Reducing resources without review can cause unexpected issues.

### CNPg Database Resource Changes

CNPg performs controlled switchovers when resource specs change, which can take several minutes per instance. To speed up the process:

```bash
# Scale down to 0 instances before pushing resource changes
kubectl patch cluster -n <namespace> <cluster-name> --type merge -p '{"spec":{"instances":0}}'

# After pushing, scale back up
kubectl patch cluster -n <namespace> <cluster-name> --type merge -p '{"spec":{"instances":1}}'
```

This avoids the switchover process and the instance starts fresh with new resources.

---

## Reference: Resource Tiers

Aligned with priority classes in `cluster/flux/meta/priority-classes.yaml`.

> **See also**: [docs/workload-classification.md](../../docs/workload-classification.md) for the authoritative workload classification reference.

| Priority Class          | CPU Limit Policy         | Rationale                                    |
| ----------------------- | ------------------------ | -------------------------------------------- |
| critical-infrastructure | No CPU limit             | Must never be throttled - cluster fails      |
| high-priority           | 5x request               | High burst headroom for essential services   |
| standard                | 3x request               | Moderate burst capacity                      |
| low-priority            | 2x request               | Limited burst, can tolerate throttling       |
| best-effort             | 1x (limit = request)     | No burst, preemptible workloads              |

### Classification Guidelines

| Priority Class          | Criteria                                              | Examples                                                                                                  |
| ----------------------- | ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| critical-infrastructure | Cluster won't function without it; CNI, DNS, storage  | cilium, traefik, rook-ceph-\*, cnpg-\*, flux-\*, cert-manager, external-secrets, technitium, kyverno      |
| high-priority           | User-facing auth, monitoring, cluster utilities       | authentik-\*, victoria-metrics-\*, grafana, reloader, chrony, valkey, spegel, vaultwarden, velero         |
| standard                | Business applications with availability expectations  | n8n-\*, qdrant, mosquitto, technitium-secondary, external-dns                                             |
| low-priority            | Internal tools, gaming, hobby projects                | headlamp, redisinsight, whoami, minecraft-\*, foundryvtt                                                  |
| best-effort             | Batch jobs, cron tasks, one-off workloads             | backup jobs, maintenance tasks                                                                            |

### Reclassification Triggers

- Workload causes cluster instability when throttled → promote to higher tier
- Low P99 but high burst causing throttling → consider removing limit or promoting
- New dependency identified (app X depends on app Y) → Y should be >= X's tier

---

## Step 4: Update Prompt Documentation

Before pushing, update this prompt if any issues were found:

- **Container mappings**: Add any new containers to the table in Step 2 if they weren't listed
- **Tier definitions**: Update tier lists if apps were added/removed or reclassified
- **Decision matrix**: Refine thresholds or actions if the current guidance proved incorrect
- **Query improvements**: Update queries if they needed modification to work correctly
- **Missing steps**: Add any steps that were needed but not documented

Commit prompt updates separately from resource changes with message:
`docs(prompts): update quarterly resource review`

---

## Step 5: Validate After Push

After pushing all commits, wait 30 minutes for metrics to stabilize, then:

```bash
# Re-run throttle query - all containers should be <5%
# Check no pods pending
kubectl get pods -A | grep -i pending

# Check recent OOMKills
kubectl get events -A --field-selector reason=OOMKilled --sort-by='.lastTimestamp' | tail -10
```

Clean up query pods after validation:

```bash
kubectl -n dev-debug delete pod -l app.kubernetes.io/purpose=metrics-query --ignore-not-found 2>/dev/null || true
```
