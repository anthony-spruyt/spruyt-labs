# Workload Classification

Defines priority tiers for all cluster workloads. Priority classes control scheduling precedence and preemption behavior during resource contention.

## Priority Classes

Defined in `cluster/flux/meta/priority-classes.yaml`:

| Priority Class | Value | Preemption | Use Case |
|----------------|-------|------------|----------|
| `system-node-critical` | 2,000,001,000 | Yes | Node-level system components |
| `system-cluster-critical` | 2,000,000,000 | Yes | Kubernetes system components |
| `critical-infrastructure` | 1,000,000 | Yes | Cluster won't function without it |
| `high-priority` | 100,000 | Yes | Essential user-facing services, observability |
| `standard` | 10,000 | Yes | Business applications (global default) |
| `low-priority` | 1,000 | Yes | Internal tools, gaming, hobby projects |
| `best-effort` | 100 | Never | Batch jobs, preemptible workloads |

## Classification Criteria

### critical-infrastructure

**Criteria**: Cluster won't function without it. Core networking, storage, secrets management, DNS.

| Namespace | Workload | Rationale |
|-----------|----------|-----------|
| kube-system | cilium, cilium-operator | CNI - no networking without it |
| kube-system | cilium-envoy | L7 proxy for Cilium |
| cert-manager | cert-manager, cainjector, webhook | TLS certificates for all services |
| cloudflare-system | cloudflared | External access tunnel |
| cnpg-system | cnpg-operator, plugin-barman-cloud | PostgreSQL operator - databases fail without it |
| external-secrets | external-secrets | Secrets delivery to namespaces |
| kubelet-csr-approver | kubelet-csr-approver | Node certificate approval |
| kyverno | all controllers | Policy enforcement, resource generation |
| rook-ceph | rook-ceph-operator, mon, mgr, osd | Storage - PVCs fail without it |
| technitium | technitium | Primary DNS server |
| traefik | traefik | Ingress - no internal routing without it |
| irq-balance | irq-balance-* | Interrupt balancing for performance |

### high-priority

**Criteria**: Essential user-facing services, observability, auth, cluster utilities. Cluster functions but operations are impacted.

| Namespace | Workload | Rationale |
|-----------|----------|-----------|
| authentik-system | authentik-server, authentik-worker | SSO authentication |
| authentik-system | authentik-cnpg-cluster | Auth database |
| chrony | chrony | Time synchronization |
| flux-system | flux-operator | GitOps operator |
| observability | grafana, vmagent, vmalert, vmsingle, vmalertmanager | Monitoring stack |
| reloader | reloader | Config reload automation |
| spegel | spegel | Container image caching |
| valkey-system | valkey | Redis-compatible cache |
| vaultwarden | vaultwarden | Password manager |
| velero | velero, node-agent | Backup and DR |

### standard (default)

**Criteria**: Business applications with availability expectations. Not critical for cluster operations.

| Namespace | Workload | Rationale |
|-----------|----------|-----------|
| n8n-system | n8n, n8n-worker, n8n-webhook, n8n-cnpg-cluster | Workflow automation |
| n8n-system | ak-outpost-n8n-outpost | Authentik outpost |
| observability | victoria-logs-single, vector | Log aggregation |
| observability | victoria-metrics-operator, kube-state-metrics | Metrics operators |
| qdrant-system | qdrant | Vector database |
| mosquitto | mosquitto | MQTT broker |
| csi-addons-system | csi-addons-controller-manager | CSI extensions |
| kube-system | snapshot-controller | Volume snapshots |
| kube-system | hubble-relay, hubble-ui | Cilium observability |
| rook-ceph | crashcollector, exporter, tools, rgw, csi-controller | Ceph auxiliary services |
| sungather | sungather | Solar monitoring |
| technitium | technitium-secondary | Secondary DNS |
| external-dns | external-dns-technitium | DNS record management |

### low-priority

**Criteria**: Internal tools, gaming, hobby projects. Can tolerate preemption.

| Namespace | Workload | Rationale |
|-----------|----------|-----------|
| headlamp-system | headlamp | Kubernetes dashboard |
| minecraft | minecraft-bedrock-*, bedrock-connect | Gaming servers |
| foundryvtt | foundryvtt | Gaming (D&D) |
| redisinsight | redisinsight | Redis GUI |
| whoami | whoami | Test/debug service |

### best-effort

**Criteria**: Batch jobs, maintenance tasks. Preemptible, no guaranteed resources.

Currently no persistent workloads. Used by:
- Backup jobs
- Maintenance CronJobs
- One-off tasks

## Flux Controllers (system-cluster-critical)

These use Kubernetes built-in priority classes:

| Controller | Priority Class |
|------------|----------------|
| helm-controller | system-cluster-critical |
| kustomize-controller | system-cluster-critical |
| source-controller | system-cluster-critical |
| notification-controller | (none - should be added) |

## Rook Ceph CSI (system-node-critical)

| Controller | Priority Class |
|------------|----------------|
| rbd.csi.ceph.com-ctrlplugin | system-node-critical |
| rbd.csi.ceph.com-nodeplugin | system-cluster-critical |
| rbd.csi.ceph.com-nodeplugin-csi-addons | system-cluster-critical |

## Classification Guidelines

### Promotion Triggers

- Workload causes cluster instability when throttled
- Other critical services depend on it
- Outage impacts ability to recover from other failures

### Demotion Triggers

- Workload can be offline without impacting cluster operations
- Only affects single user/use case
- Has external fallback (e.g., external DNS, public registries)

### Review Process

Run `.claude/prompts/workload-classification-review.md` quarterly or when:
- Adding new workloads
- Changing dependencies between services
- After incidents involving resource contention

## Related

- [quarterly-resource-review.md](../.claude/prompts/quarterly-resource-review.md) - Resource optimization
- [cluster/flux/meta/priority-classes.yaml](../cluster/flux/meta/priority-classes.yaml) - Priority class definitions
