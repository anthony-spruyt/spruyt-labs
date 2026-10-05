# Workload Classification

Priority tiers for cluster workloads. Priority classes decide scheduling order and who gets preempted when a node runs out of resources.

## Priority Classes

Defined in [`cluster/flux/meta/priority-classes.yaml`](../cluster/flux/meta/priority-classes.yaml). `standard` is the global default, so a workload that sets nothing lands there.

| Priority Class            | Value         | Preempts others | Use Case                                      |
| ------------------------- | ------------- | --------------- | --------------------------------------------- |
| `system-node-critical`    | 2,000,001,000 | Yes             | Built-in. Per-node system components          |
| `system-cluster-critical` | 2,000,000,000 | Yes             | Built-in. Kubernetes and Flux controllers     |
| `critical-infrastructure` | 1,000,000     | Yes             | Cluster won't function without it             |
| `high-priority`           | 100,000       | Yes             | Essential user-facing services, observability |
| `standard`                | 10,000        | Yes             | Business applications (global default)        |
| `low-priority`            | 1,000         | Yes             | Internal tools, gaming, hobby projects, MCPs  |
| `best-effort`             | 100           | Never           | Preemptible batch work (currently unused)     |

## CPU Limit Policy

Unbounded CPU on these small nodes causes thermal throttling that slows every pod on the node, including critical ones. Limits are set per tier:

| Priority Class            | CPU Limit            | Rationale                                  |
| ------------------------- | -------------------- | ------------------------------------------ |
| `critical-infrastructure` | None                 | Throttling these breaks the whole cluster  |
| `high-priority`           | 5x request           | High burst headroom for essential services |
| `standard`                | 3x request           | Moderate burst capacity                    |
| `low-priority`            | 2x request           | Limited burst, can tolerate throttling     |
| `best-effort`             | 1x (limit = request) | No burst, preemptible workloads            |

## Current Assignments

Taken from the live cluster. When adding a workload, set `priorityClassName` explicitly and add it here.

### critical-infrastructure

Core networking, storage, secrets, DNS, and the UPS shutdown path.

| Namespace            | Workload                                            | Rationale                                       |
| -------------------- | --------------------------------------------------- | ----------------------------------------------- |
| cert-manager         | cert-manager, cainjector, webhook                   | TLS certificates for all services               |
| cloudflare-system    | cloudflared                                         | External access tunnel                          |
| cnpg-system          | cnpg-operator, plugin-barman-cloud                  | PostgreSQL operator - databases fail without it |
| external-secrets     | external-secrets (controller only)                  | Secrets delivery to namespaces                  |
| irq-balance          | irq-balance-e2, irq-balance-ms-01                   | Interrupt placement on every node               |
| kube-system          | kata-tap-qdisc-fix                                  | Kata VM networking fix on every node            |
| kubelet-csr-approver | kubelet-csr-approver                                | Kubelet serving certificate approval            |
| kyverno              | admission, background, cleanup, reports controllers | Policy enforcement, resource generation         |
| nut-system           | nut-server, shutdown-orchestrator                   | UPS monitoring and graceful power-loss shutdown |
| rook-ceph            | rook-ceph-operator, mon, mgr, osd                   | Storage - PVCs fail without it                  |
| technitium           | technitium                                          | Primary DNS server                              |
| traefik              | traefik                                             | Ingress                                         |

### high-priority

Cluster works without these, but operating it is impaired.

| Namespace        | Workload                                                                                                                                         | Rationale                 |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------- |
| authentik-system | authentik-server, authentik-worker, authentik-cnpg-cluster                                                                                       | SSO and its database      |
| chrony           | chrony                                                                                                                                           | Time synchronization      |
| falco-system     | falco (DaemonSet), falcosidekick                                                                                                                 | Runtime security alerting |
| flux-system      | flux-operator                                                                                                                                    | GitOps operator           |
| kube-system      | descheduler (CronJob)                                                                                                                            | Pod rebalancing           |
| litellm          | litellm-valkey                                                                                                                                   | LLM gateway cache         |
| observability    | grafana, kube-state-metrics, victoria-metrics-operator, vmagent, vmalert, vmalertmanager, vmsingle, victoria-logs-single, victoria-traces-single | Monitoring stack          |
| reloader         | reloader                                                                                                                                         | Config reload on change   |
| spegel           | spegel                                                                                                                                           | Container image caching   |
| valkey-system    | valkey                                                                                                                                           | Redis-compatible cache    |
| vaultwarden      | vaultwarden                                                                                                                                      | Password manager          |
| velero           | velero, node-agent                                                                                                                               | Backup and DR             |
| vpa-system       | admission-controller, recommender, updater                                                                                                       | Resource recommendations  |

### standard

Explicitly set or inherited from the global default. Includes, among others: agent-worker-system, coder, happy-server, n8n and its CNPG cluster and poolers, litellm (except its Valkey), temporal, nexus, qdrant, mosquitto, sungather, technitium-secondary, external-dns-technitium, csi-addons-controller-manager, snapshot-controller, hubble-relay, hubble-ui, vector and node-exporter, the Ceph
auxiliaries (crashcollector, exporter, tools, rgw, rook-discover, ceph-csi-controller-manager), every Authentik outpost, and all other CronJobs.

### low-priority

Can tolerate preemption.

| Namespace        | Workload                                                  | Rationale            |
| ---------------- | --------------------------------------------------------- | -------------------- |
| brave-search-mcp | brave-search-mcp                                          | Agent tooling        |
| foundryvtt       | foundryvtt                                                | Gaming (D&D)         |
| headlamp-system  | headlamp                                                  | Kubernetes dashboard |
| minecraft        | crafty-controller, bedrock-connect                        | Gaming servers       |
| n8n-mcp          | n8n-mcp-server                                            | Agent tooling        |
| observability    | mcp-victorialogs, mcp-victoriametrics, mcp-victoriatraces | Agent tooling        |
| redisinsight     | redisinsight                                              | Redis GUI            |
| unifi-mcp        | unifi-network-mcp                                         | Agent tooling        |
| unifi-system     | unpoller                                                  | UniFi metrics        |
| whoami           | whoami                                                    | Test/debug service   |

### best-effort

No workloads use it today.

### Built-in classes

| Workload                                                                          | Priority Class            |
| --------------------------------------------------------------------------------- | ------------------------- |
| cilium, cilium-envoy, cilium-operator                                             | `system-node-critical`    |
| Ceph CSI node plugins (rbd and its csi-addons sidecars)                           | `system-node-critical`    |
| Ceph CSI controller plugins (rbd)                                                 | `system-cluster-critical` |
| helm-controller, kustomize-controller, notification-controller, source-controller | `system-cluster-critical` |
| coredns, metrics-server, kube-apiserver, controller-manager, scheduler            | `system-cluster-critical` |

## Known Gaps

Workloads whose live priority does not match the intended tier:

| Workload                                     | Live       | Intended     | Cause                                 |
| -------------------------------------------- | ---------- | ------------ | ------------------------------------- |
| external-secrets cert-controller and webhook | `standard` | unclassified | Only the controller's priority is set |

## Classification Guidelines

### Promotion Triggers

- Workload causes cluster instability when throttled
- Other critical services depend on it
- Outage impacts ability to recover from other failures

### Demotion Triggers

- Workload can be offline without impacting cluster operations
- Only affects single user/use case
- Has external fallback (e.g., external DNS, public registries)

### Review

Compare this page against the live cluster quarterly, and when adding workloads or after an incident involving resource contention:

```bash
kubectl get deploy,sts,ds -A \
  -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,PRIORITY:.spec.template.spec.priorityClassName'
```

An empty `PRIORITY` column means the pod falls back to `standard`.
