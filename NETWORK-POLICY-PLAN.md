# CiliumNetworkPolicy Rollout Plan

## Completed (22 namespaces have policies)

### Previously Completed
- kubelet-csr-approver (2 pods) ✓
- reloader (1 pod) ✓
- csi-addons-system (1 pod) ✓
- redisinsight (2 pods) ✓
- headlamp-system (1 pod) ✓
- mosquitto (1 pod) ✓
- whoami (1 pod) ✓
- firefly-iii (3 pods) ✓
- foundryvtt (1 pod) ✓
- vaultwarden (1 pod) ✓
- n8n-system (6 pods) ✓
- authentik-system (5 pods) ✓

### Phase 3: Simple Services ✓
- **sungather** (1 pod) ✓
  - DNS egress, Modbus TCP 502 egress (world), MQTT egress to mosquitto (1883)
- **chrony** (3 pods) ✓
  - DNS egress, NTP UDP 123 egress/ingress (world), NTS TCP 4460 egress (world)

### Phase 4: Simple Apps ✓
- **minecraft** (5 pods) ✓
  - bedrock-connect: DNS, HTTPS 443 egress (Xbox auth), UDP 19132 ingress (world)
  - minecraft-bedrock-survival: DNS, HTTPS 443 egress (Xbox auth), UDP 19132 ingress (world)
  - minecraft-bedrock-creative: DNS, HTTPS 443 egress (Xbox auth), UDP 19132 ingress (world)
  - maintenance CronJob: DNS, kube-apiserver egress (uses matchExpressions for job pods)
- **nut-system** (1 pod) ✓
  - DNS egress, NUT TCP 3493 ingress (world), metrics TCP 9199 ingress (vmagent)

### Phase 5: System Pods ✓
- **irq-balance** (6 pods) ✓ - Privileged system daemon, deny-all policy (defense-in-depth)
- **spegel** (6 pods) ✓ - Image cache (has CNPs: metrics, p2p, https egress)

### Phase 6: Simple Operators (13 pods total)
- **external-dns** (1 pod) ✓ - kube-apiserver 6443, TCP 53 to technitium pods (RFC2136 via LB→DNAT), metrics 7979
- **cloudflare-system** (3 pods) ✓ - edge egress (7844 UDP, 443 TCP), traefik 8443, flux webhook 9292, metrics 8080
- **cert-manager** (6 pods) ✓ - controller (kube-api, ACME 443, DNS 53), cainjector/webhook (kube-api), metrics 9402
- **external-secrets** (3 pods) ✓ - Secret sync (kube-api, Kubernetes provider only), metrics 8080

### Phase 7: Databases (6 pods total) ✓
- **valkey-system** (1 pod) ✓ - Redis (ingress from n8n, redisinsight, authentik; metrics 9121)
- **qdrant-system** (1 pod) ✓ - Vector DB (traefik, n8n, internal-cluster, metrics)
- **cnpg-system** (2 pods) ✓ - Postgres operator (kube-api, webhook, cluster comms, barman, metrics)
- **technitium** (2 pods) ✓ - DNS server (fromEntities: all for DNS ingress, world egress for recursion/blocklists, catalog zone sync)

## Remaining (6 namespaces need policies)

### Phase 8: Security (12 pods total)
- **kyverno** (4 pods) - Policy engine (kube-api, webhook ingress)
- **falco-system** (8 pods) - Runtime security (kernel/host access)

### Phase 9: Complex - Observability & Backup (31 pods total)
- **observability** (17 pods) - VM stack, Grafana (vmagent scrapes ALL namespaces)
- **velero** (14 pods) - Backup (S3 egress, kube-api)

### Phase 10: Complex - Networking & Storage (38 pods total)
- **traefik** (1 pod) - Ingress controller (world ingress, egress to ALL backends)
- **rook-ceph** (37 pods) - Storage (OSD mesh, MGR, MON, MDS - very complex)

## Lessons Learned

### Debugging Tips
1. **App logs > hubble for startup failures** - Hubble ring buffer overflows lose events; check pod logs first when apps crash
2. **"default" source in metrics** - Can be transient/historical, not always active drops. May appear when source identity can't be determined
3. **Test after deploy** - Don't just rely on hubble; actually test the application (e.g., connect via Minecraft client)

### Policy Patterns Discovered
1. **Host entity is allowed by default** - Kubelet health probes don't need explicit `fromEntities: host`
2. **Game servers need auth egress** - Bedrock-connect needs HTTPS 443 egress for Xbox/Microsoft discovery (`client.discovery.minecraft-services.net`)
3. **CronJob pods** - Use `matchExpressions` with `batch.kubernetes.io/job-name: Exists` to match dynamically-named job pods
4. **Always check what app actually does** - Don't assume from README; check GitHub repo, issues, and actual runtime behavior
5. **Spegel stale DHT entries cause transient drops** - Spegel's DHT has hardcoded 10-minute TTL. When pod IPs get recycled within that window (e.g., during rollouts), spegel tries to connect to stale entries. Traffic reaches the new pod but gets denied by its CNP → POLICY_DENIED drops. These are expected transient noise, not a CNP bug. Spegel needs `toEntities: cluster` (not `toEndpoints: spegel`) because stricter policies break when DHT has stale IPs that no longer match current spegel pod endpoints.

### Common Mistakes to Avoid
- Don't skip HTTPS egress for apps that do external API calls (Xbox auth, OAuth, etc.)
- Don't assume documentation lists all required connections
- Always validate with actual app usage, not just "no drops in hubble"

### CNP Naming in Shared Namespaces (Technitium)
1. **CNPs must have unique names within a namespace** - Multiple apps in same namespace (e.g., technitium + technitium-secondary) will overwrite each other's CNPs if names match
2. **Prefix CNP names with app name** - Use `technitium-allow-dns-ingress` not `allow-dns-ingress`
3. **Use `fromEntities: all` for DNS servers** - DNS should accept queries from any source (world + cluster + host + everything)
4. **Hubble is unreliable** - Check actual logs and observability dashboards, not just hubble observe

### redis_exporter Authentication (Valkey/Redis ACL)
1. **Distroless images have no shell** - Can't use shell wrappers (`/bin/sh -c`), must use native env vars/args
2. **Password file format is JSON** - `{"redis://user@host:port": "password"}`, NOT plain text
3. **Password file key must include username** - When using `--redis.user=metrics`, the lookup constructs full URI `redis://metrics@localhost:6379` before matching
4. **Valkey ACL categories** - `+@server` is invalid in Valkey; use specific commands like `+info +client +config|get`
5. **Check source code for auth flow** - redis_exporter `lookupPasswordInPasswordMap()` shows exact URI construction logic

## Workflow (ONE workload at a time)

### For Each Workload
1. Research what the app actually does (GitHub, logs, existing traffic)
2. Create/update network-policies.yaml
3. Run qa-validator
4. Fix any issues, re-run qa-validator until APPROVED
5. Commit
6. Push (user does manually)
7. Run cluster-validator
8. **Test the actual application** (not just check for drops)
9. Check hubble/Grafana for drops
10. If drops found or app broken → fix → repeat from step 2
11. Only move to next workload when current is confirmed working

## Key Patterns Reference

```yaml
# DNS egress (standard for all apps)
- toServices:
    - k8sService:
        serviceName: kube-dns
        namespace: kube-system
  toPorts:
    - ports:
        - port: "53"
          protocol: UDP
        - port: "53"
          protocol: TCP

# Cross-namespace pod communication
- toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: target-namespace
        k8s:app.kubernetes.io/name: target-app

# World egress (external APIs, HTTPS)
- toEntities:
    - world
  toPorts:
    - ports:
        - port: "443"
          protocol: TCP

# World ingress (LoadBalancer services)
- fromEntities:
    - world
  toPorts:
    - ports:
        - port: "19132"
          protocol: UDP

# Metrics ingress from vmagent
- fromEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: observability
        k8s:app.kubernetes.io/name: vmagent

# CronJob/Job pods (dynamic names)
endpointSelector:
  matchExpressions:
    - key: batch.kubernetes.io/job-name
      operator: Exists

# Kube-apiserver egress
- toEntities:
    - kube-apiserver
```
