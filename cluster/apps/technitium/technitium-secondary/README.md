# Technitium Secondary - DNS Server Replica

## Overview

Technitium Secondary is a replica DNS server that provides redundant DNS services and load balancing for the spruyt-labs homelab infrastructure. This secondary instance works in conjunction with the primary Technitium DNS server to ensure high availability and fault tolerance for DNS resolution.

## Directory Layout

```yaml
technitium-secondary/
├── app/
│   ├── kustomization.yaml            # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── release.yaml                # Helm release configuration
│   ├── values.yaml                 # Helm values
│   ├── certificate.yaml            # TLS certificate
│   ├── persistent-volume-claim.yaml # Storage configuration
│   └── pod-disruption-budget.yaml  # Availability configuration
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Primary Technitium DNS server deployed
- Persistent storage for DNS zone data
- Network connectivity for DNS traffic (UDP/TCP port 53)
- Proper RBAC permissions for DNS operations
- Zone transfer configuration between primary and secondary

## Operation

### Procedures

1. **DNS zone synchronization**:

   ```bash
   # Check zone transfer status
   kubectl exec -it <technitium-secondary-pod> -n technitium -- technitium check-sync

   # Monitor zone transfer logs
   kubectl logs -n technitium <technitium-secondary-pod> | grep "transfer"
   ```

2. **Performance monitoring**:

   ```bash
   # Check DNS performance
   kubectl top pods -n technitium | grep secondary

   # Monitor response times
   kubectl logs -n technitium <technitium-secondary-pod> | grep "response"
   ```

3. **Configuration updates**:

   ```bash
   # Update Technitium Secondary configuration
   kubectl apply -f values.yaml

   # Restart pods for configuration changes
   kubectl rollout restart deployment technitium-secondary -n technitium
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate DNS zone synchronization
kubectl exec -it <technitium-secondary-pod> -n technitium -- technitium check-sync

# Expected: Synchronization status displayed

# Validate performance monitoring
kubectl top pods -n technitium | grep secondary

# Expected: Resource usage for secondary pod

# Validate configuration updates
kubectl get pods -n technitium --no-headers | grep secondary | grep 'Running'

# Expected: Secondary pod running after restart
```

### Decision Trees

```yaml
# Technitium Secondary operational decision tree
start: "technitium_secondary_health_check"
nodes:
  technitium_secondary_health_check:
    question: "Is Technitium Secondary healthy?"
    command: "kubectl get pods -n technitium --no-headers | grep secondary | grep -v 'Running'"
    yes: "investigate_issue"
    no: "technitium_secondary_healthy"
  investigate_issue:
    action: "kubectl describe pods -n technitium | grep secondary | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      zone_sync_failure: "Zone synchronization failure"
      network_connectivity: "Network connectivity issue"
      resource_constraint: "Resource limitation"
      configuration_error: "Configuration mismatch"
  zone_sync_failure:
    action: "Check zone transfer: kubectl exec -it <technitium-secondary-pod> -n technitium -- technitium check-sync"
    next: "apply_fix"
  network_connectivity:
    action: "Test network connectivity: kubectl exec -it <test-pod> -n technitium -- ping technitium-secondary"
    next: "apply_fix"
  resource_constraint:
    action: "Check resource usage: kubectl top pods -n technitium | grep secondary"
    next: "apply_fix"
  configuration_error:
    action: "Review values.yaml and secondary configuration"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n technitium --no-headers | grep secondary | grep 'Running'"
    yes: "technitium_secondary_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  technitium_secondary_healthy:
    action: "Technitium Secondary verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# Technitium Secondary cross-service dependencies
service_dependencies:
  technitium_secondary:
    depends_on:
      - kube-system/cilium
      - observability/victoria-metrics-k8s-stack
      - rook-ceph/rook-ceph
      - cert-manager/cert-manager
      - technitium/technitium
    depended_by:
      - All services requiring DNS resolution
      - All internal domain services
      - All workloads using DNS
    critical_path: true
    health_check_command: "kubectl get pods -n technitium --no-headers | grep secondary | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Zone synchronization failures**:

   - **Symptom**: Secondary not receiving zone updates
   - **Diagnosis**: Check zone transfer logs and configuration
   - **Resolution**: Verify zone transfer settings and network connectivity

2. **DNS resolution inconsistencies**:

   - **Symptom**: Different responses from primary and secondary
   - **Diagnosis**: Compare zone data between instances
   - **Resolution**: Force zone transfer and verify consistency

3. **Performance bottlenecks**:

   - **Symptom**: High DNS query latency on secondary
   - **Diagnosis**: Monitor DNS performance metrics
   - **Resolution**: Scale resources or optimize DNS configuration

4. **Network connectivity problems**:

   - **Symptom**: Secondary unreachable or intermittent
   - **Diagnosis**: Test network connectivity and DNS
   - **Resolution**: Verify network policies and service discovery

## Maintenance

### Updates

```bash
# Update Technitium Secondary using Flux
flux reconcile kustomization technitium-secondary --with-source

# Check update status
kubectl get helmreleases -n technitium | grep secondary
```

### Zone Synchronization

```bash
# Force zone transfer
kubectl exec -it <technitium-secondary-pod> -n technitium -- technitium force-sync

# Check synchronization status
kubectl exec -it <technitium-secondary-pod> -n technitium -- technitium sync-status
```

### MCP Integration

- **Library ID**: `technitium-dns-secondary`
- **Version**: `v11.0.0`
- **Usage**: Redundant authoritative DNS server
- **Citation**: Use `resolve-library-id` for Technitium Secondary configuration

## References

- [Technitium Documentation](https://technitium.com/dns/)
- [DNS Zone Transfer Guide](https://www.rfc-editor.org/rfc/rfc5936)
- [Kubernetes High Availability](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/)
- [DNS Redundancy Best Practices](https://www.ietf.org/rfc/rfc2182.txt)

## Agent-Friendly Workflows

### Technitium Secondary Health Check Workflow

```yaml
# Technitium Secondary health check decision tree
start: "check_technitium_secondary_pods"
nodes:
  check_technitium_secondary_pods:
    question: "Are Technitium Secondary pods running?"
    command: "kubectl get pods -n technitium -l app.kubernetes.io/name=technitium-secondary --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_zone_synchronization"
    no: "restart_secondary_pods"
  check_zone_synchronization:
    question: "Is zone synchronization working?"
    command: "kubectl exec -n technitium deployment/technitium-secondary -- technitium check-sync 2>/dev/null | grep -c 'success\\|ok' || echo '0'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "SYNC_FAIL"}'' | grep -q ''OK'''
    yes: "check_secondary_dns_resolution"
    no: "fix_zone_sync"
  check_secondary_dns_resolution:
    question: "Is DNS resolution working on secondary?"
    command: "kubectl exec -n technitium deployment/technitium-secondary -- nslookup kubernetes.default.svc.cluster.local 127.0.0.1 | grep -c 'Address:'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "FAIL"}'' | grep -q ''OK'''
    yes: "technitium_secondary_healthy"
    no: "fix_secondary_dns"
  restart_secondary_pods:
    action: "Restart Technitium Secondary pods"
    next: "check_technitium_secondary_pods"
  fix_zone_sync:
    action: "Fix zone synchronization with primary server"
    next: "check_zone_synchronization"
  fix_secondary_dns:
    action: "Check secondary DNS configuration and zone data"
    next: "check_secondary_dns_resolution"
  technitium_secondary_healthy:
    action: "Technitium Secondary DNS service is healthy and synchronized"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for Technitium Secondary documentation.
- Confirm the catalog entry contains the documentation or API details needed for Technitium Secondary operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers Technitium Secondary documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed Technitium Secondary configuration changes.

### When Technitium Secondary documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in Technitium Secondary change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting Technitium Secondary documentation.
