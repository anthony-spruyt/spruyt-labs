# Technitium - DNS Server

## Overview

Technitium is a powerful, open-source DNS server that provides authoritative DNS services. In the spruyt-labs homelab infrastructure, Technitium serves as the primary DNS server for internal domain resolution, providing reliable and configurable DNS services for the homelab environment.

## Directory Layout

```yaml
technitium/
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
- Persistent storage for DNS zone data
- Network connectivity for DNS traffic (UDP/TCP port 53)
- Proper RBAC permissions for DNS operations
- TLS certificates for secure DNS operations

## Operation

### Procedures

1. **DNS zone management**:

   ```bash
   # Check DNS zones
   kubectl exec -it <technitium-pod> -n technitium -- technitium list-zones

   # Monitor DNS queries
   kubectl logs -n technitium <technitium-pod> | grep "query"
   ```

2. **Performance monitoring**:

   ```bash
   # Check DNS performance
   kubectl top pods -n technitium

   # Monitor response times
   kubectl logs -n technitium <technitium-pod> | grep "response"
   ```

3. **Configuration updates**:

   ```bash
   # Update Technitium configuration
   kubectl apply -f values.yaml

   # Restart pods for configuration changes
   kubectl rollout restart deployment technitium -n technitium
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate DNS zone management
kubectl exec -it <technitium-pod> -n technitium -- technitium list-zones

# Expected: DNS zones listed

# Validate performance monitoring
kubectl top pods -n technitium

# Expected: Resource usage displayed

# Validate configuration updates
kubectl get pods -n technitium --no-headers | grep 'Running'

# Expected: Pods running after restart
```

### Decision Trees

```yaml
# Technitium operational decision tree
start: "technitium_health_check"
nodes:
  technitium_health_check:
    question: "Is Technitium healthy?"
    command: "kubectl get pods -n technitium --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "technitium_healthy"
  investigate_issue:
    action: "kubectl describe pods -n technitium | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      dns_resolution: "DNS resolution failure"
      zone_configuration: "Zone configuration problem"
      resource_constraint: "Resource limitation"
      network_connectivity: "Network connectivity issue"
  dns_resolution:
    action: "Test DNS resolution: kubectl exec -it <test-pod> -n technitium -- nslookup example.com"
    next: "apply_fix"
  zone_configuration:
    action: "Check zone configuration: kubectl exec -it <technitium-pod> -n technitium -- technitium show-zone <zone>"
    next: "apply_fix"
  resource_constraint:
    action: "Check resource usage: kubectl top pods -n technitium"
    next: "apply_fix"
  network_connectivity:
    action: "Test network connectivity: kubectl exec -it <test-pod> -n technitium -- ping technitium"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n technitium --no-headers | grep 'Running'"
    yes: "technitium_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  technitium_healthy:
    action: "Technitium verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# Technitium cross-service dependencies
service_dependencies:
  technitium:
    depends_on:
      - kube-system/cilium
      - observability/victoria-metrics-k8s-stack
      - rook-ceph/rook-ceph
      - cert-manager/cert-manager
    depended_by:
      - All services requiring DNS resolution
      - All internal domain services
      - All workloads using DNS
    critical_path: true
    health_check_command: "kubectl get pods -n technitium --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **DNS resolution failures**:

   - **Symptom**: DNS queries failing or timing out
   - **Diagnosis**: Check DNS logs and zone configuration
   - **Resolution**: Verify zone files and DNS records

2. **Zone transfer problems**:

   - **Symptom**: Zone transfer failures
   - **Diagnosis**: Check zone transfer logs
   - **Resolution**: Verify zone transfer configuration

3. **Performance bottlenecks**:

   - **Symptom**: High DNS query latency
   - **Diagnosis**: Monitor DNS performance metrics
   - **Resolution**: Scale resources or optimize DNS configuration

4. **TLS certificate issues**:

   - **Symptom**: DNS-over-TLS failures
   - **Diagnosis**: Check certificate status
   - **Resolution**: Verify cert-manager certificate configuration

## Maintenance

### Updates

```bash
# Update Technitium using Flux
flux reconcile kustomization technitium --with-source

# Check update status
kubectl get helmreleases -n technitium
```

### Zone Management

```bash
# Add new DNS zone
kubectl exec -it <technitium-pod> -n technitium -- technitium add-zone <domain> <zone-file>

# Remove DNS zone
kubectl exec -it <technitium-pod> -n technitium -- technitium remove-zone <domain>
```

### MCP Integration

- **Library ID**: `technitium-dns-server`
- **Version**: `v11.0.0`
- **Usage**: Authoritative DNS server
- **Citation**: Use `resolve-library-id` for Technitium configuration

## References

- [Technitium Documentation](https://technitium.com/dns/)
- [DNS Protocol Reference](https://www.rfc-editor.org/rfc/rfc1035)
- [Kubernetes DNS Guide](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [DNS Security Best Practices](https://www.ietf.org/rfc/rfc2845.txt)

## Agent-Friendly Workflows

### Technitium Health Check Workflow

```yaml
# Technitium health check decision tree
start: "check_technitium_pods"
nodes:
  check_technitium_pods:
    question: "Are Technitium pods running?"
    command: "kubectl get pods -n technitium --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_dns_resolution"
    no: "restart_technitium_pods"
  check_dns_resolution:
    question: "Is DNS resolution working?"
    command: "kubectl exec -n technitium deployment/technitium -- nslookup kubernetes.default.svc.cluster.local 127.0.0.1 | grep -c 'Address:'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "FAIL"}'' | grep -q ''OK'''
    yes: "check_dns_zones"
    no: "fix_dns_resolution"
  check_dns_zones:
    question: "Are DNS zones loaded?"
    command: "kubectl exec -n technitium deployment/technitium -- technitium list-zones 2>/dev/null | grep -c 'zone' || echo '0'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "NO_ZONES"}'' | grep -q ''OK'''
    yes: "technitium_healthy"
    no: "load_dns_zones"
  restart_technitium_pods:
    action: "Restart Technitium pods"
    next: "check_technitium_pods"
  fix_dns_resolution:
    action: "Check DNS configuration and upstream servers"
    next: "check_dns_resolution"
  load_dns_zones:
    action: "Load and configure DNS zones"
    next: "check_dns_zones"
  technitium_healthy:
    action: "Technitium DNS service is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for Technitium documentation.
- Confirm the catalog entry contains the documentation or API details needed for Technitium operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers Technitium documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed Technitium configuration changes.

### When Technitium documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in Technitium change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting Technitium documentation.
