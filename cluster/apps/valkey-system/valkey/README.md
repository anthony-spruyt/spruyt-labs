# Valky - High-Performance Key-Value Store

## Overview

Valkey is a high-performance, open-source key-value store compatible with Redis protocols. In the spruyt-labs homelab infrastructure, Valky serves as the primary caching and data storage solution for various applications, providing low-latency access to frequently used data.

## Directory Layout

```yaml
valkey/
├── app/
│   ├── kustomization.yaml            # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Storage class configured for persistent volumes
- Network connectivity between application pods
- Proper RBAC permissions for Valky operations
- Monitoring and observability stack deployed

## Operation

### Procedures

1. **Cluster management**:

```bash
# Check cluster status
kubectl exec -it valkey-0 -n valkey-system -- valkey-cli cluster info

# Monitor cluster health
kubectl exec -it valkey-0 -n valkey-system -- valkey-cli cluster nodes
```

2. **Performance monitoring**:

```bash
# Check memory usage
kubectl exec -it valkey-0 -n valkey-system -- valkey-cli info memory

# Monitor connections
kubectl exec -it valkey-0 -n valkey-system -- valkey-cli info clients
```

3. **Backup operations**:

```bash
# Trigger manual backup
kubectl exec -it valkey-0 -n valkey-system -- valkey-cli save

# Check backup status
kubectl exec -it valkey-0 -n valkey-system -- valkey-cli lastsave
```

### Decision Trees

```yaml
# Valky operational decision tree
start: "valkey_health_check"
nodes:
  valkey_health_check:
    question: "Is Valky healthy?"
    command: "kubectl get pods -n valkey-system --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "valkey_healthy"
  investigate_issue:
    action: "kubectl describe pods -n valkey-system | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      memory_pressure: "Memory pressure or eviction"
      network_issue: "Network connectivity problem"
      persistence_failure: "Persistence or storage issue"
      configuration_error: "Configuration mismatch"
  memory_pressure:
    action: "Check memory usage: kubectl exec -it valkey-0 -n valkey-system -- valkey-cli info memory"
    next: "apply_fix"
  network_issue:
    action: "Test network connectivity: kubectl exec -it valkey-0 -n valkey-system -- valkey-cli ping"
    next: "apply_fix"
  persistence_failure:
    action: "Check persistent volume: kubectl get pvc -n valkey-system"
    next: "apply_fix"
  configuration_error:
    action: "Review values.yaml and Helm configuration"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n valkey-system --no-headers | grep 'Running'"
    yes: "valkey_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  valkey_healthy:
    action: "Valky verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# Valky cross-service dependencies
service_dependencies:
  valkey:
    depends_on:
      - kube-system/cilium
      - observability/victoria-metrics-k8s-stack
      - rook-ceph/rook-ceph
    depended_by:
      - All applications using caching
      - All services requiring key-value storage
      - All workloads needing low-latency data access
    critical_path: true
    health_check_command: "kubectl get pods -n valkey-system --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Memory pressure and eviction**:

   - **Symptom**: High memory usage, frequent evictions
   - **Diagnosis**: Check memory metrics and eviction statistics
   - **Resolution**: Adjust maxmemory policy or scale cluster

2. **Network connectivity problems**:

   - **Symptom**: Connection timeouts or failures
   - **Diagnosis**: Test network connectivity and DNS resolution
   - **Resolution**: Verify Cilium network policies and service discovery

3. **Persistence failures**:

   - **Symptom**: Data loss after pod restarts
   - **Diagnosis**: Check persistent volume claims and storage
   - **Resolution**: Verify Rook Ceph storage provisioning

4. **Replication issues**:

   - **Symptom**: Cluster nodes not synchronizing
   - **Diagnosis**: Check cluster status and replication
   - **Resolution**: Verify cluster configuration and connectivity

## Maintenance

### Updates

```bash
# Update Valky using Flux
flux reconcile kustomization valkey --with-source

# Check update status
kubectl get helmreleases -n valkey-system
```

### Configuration Management

```bash
# Update configuration
kubectl apply -f values.yaml

# Restart pods for configuration changes
kubectl rollout restart statefulset valkey -n valkey-system
```

### MCP Integration

- **Library ID**: `valkey-high-performance-cache`
- **Version**: `v7.2.0`
- **Usage**: High-performance key-value storage and caching
- **Citation**: Use `resolve-library-id` for Valky configuration and troubleshooting

## References

- [Valkey Documentation](https://valkey.io/)
- [Valkey Helm Chart](https://github.com/valkey-io/valkey-helm)
- [Redis Compatibility Guide](https://redis.io/docs/)
- [Kubernetes Stateful Applications](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)

## Agent-Friendly Workflows

### Valky Health Check Workflow

```yaml
# Valkey health check decision tree
start: "check_valkey_pods"
nodes:
  check_valkey_pods:
    question: "Are Valkey pods running?"
    command: "kubectl get pods -n valkey-system --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_valkey_ping"
    no: "restart_valkey_pods"
  check_valkey_ping:
    question: "Is Valkey responding to ping?"
    command: "kubectl exec -n valkey-system statefulset/valkey -- valkey-cli ping | grep -c 'PONG'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "NO_PONG"}'' | grep -q ''OK'''
    yes: "check_memory_usage"
    no: "fix_valkey_connectivity"
  check_memory_usage:
    question: "Is memory usage within limits?"
    command: 'kubectl exec -n valkey-system statefulset/valkey -- valkey-cli info memory | grep ''used_memory:'' | awk -F: ''{print $2}'' | awk ''{if ($1 < 1000000000) print "OK"; else print "HIGH_MEM"}'' | grep -q ''OK'''
    validation: "echo $? | grep -q '0'"
    yes: "valkey_healthy"
    no: "optimize_memory"
  restart_valkey_pods:
    action: "Restart Valkey pods"
    next: "check_valkey_pods"
  fix_valkey_connectivity:
    action: "Check Valkey configuration and network connectivity"
    next: "check_valkey_ping"
  optimize_memory:
    action: "Check memory configuration and eviction policies"
    next: "check_memory_usage"
  valkey_healthy:
    action: "Valkey key-value store is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for Valky documentation.
- Confirm the catalog entry contains the documentation or API details needed for Valky operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers Valky documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed Valky configuration changes.

### When Valky documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in Valky change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting Valky documentation.
