# external-dns-technitium - DNS Management

## Overview

ExternalDNS is a Kubernetes controller that automatically manages DNS records based on Kubernetes resources. The technitium variant integrates with Technitium DNS server to provide dynamic DNS management for the spruyt-labs homelab infrastructure, ensuring that DNS records are automatically created, updated, and deleted as services are deployed or removed.

## Directory Layout

```yaml
external-dns-technitium/
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
- Technitium DNS server configured and accessible
- Proper DNS zone configuration in Technitium
- API credentials for Technitium DNS server
- Network connectivity to Technitium DNS server

## Operation

### Procedures

1. **DNS record management**:

```bash
# Check external-dns service status
kubectl get pods -n external-dns

# Verify DNS record synchronization
kubectl logs -n external-dns <pod-name> | grep "record"

# Check Technitium API connectivity
kubectl logs -n external-dns <pod-name> | grep "API"
```

2. **Configuration management**:

```bash
# Check current configuration
kubectl get configmap -n external-dns

# Verify Technitium DNS server connectivity
kubectl logs -n external-dns <pod-name> | grep "Technitium"
```

3. **Performance monitoring**:

   ```bash
   # Check DNS record synchronization status
   kubectl logs -n external-dns <pod-name> | grep "synchronization"

   # Monitor API call performance
   kubectl logs -n external-dns <pod-name> | grep "API call"
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate DNS record management
kubectl logs -n external-dns <pod-name> | grep "record"

# Expected: DNS record synchronization logs

# Validate configuration management
kubectl get configmap -n external-dns

# Expected: Configuration maps listed

# Validate performance monitoring
kubectl logs -n external-dns <pod-name> | grep "synchronization"

# Expected: Synchronization status logs
```

### Decision Trees

```yaml
# external-dns-technitium operational decision tree
start: "external_dns_health_check"
nodes:
  external_dns_health_check:
    question: "Is external-dns-technitium healthy?"
    command: "kubectl get pods -n external-dns --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "external_dns_healthy"
  investigate_issue:
    action: "kubectl describe pods -n external-dns | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      technitium_connectivity: "Technitium DNS server connectivity problem"
      api_auth_error: "API authentication error"
      config_error: "Configuration mismatch"
      resource_constraint: "Resource limitation"
      network_issue: "Network connectivity"
  technitium_connectivity:
    action: "Check Technitium DNS server connectivity: kubectl logs -n external-dns <pod-name> | grep 'Technitium'"
    next: "apply_fix"
  api_auth_error:
    action: "Verify API credentials and configuration: kubectl get secrets -n external-dns"
    next: "apply_fix"
  config_error:
    action: "Review values.yaml and Helm configuration"
    next: "apply_fix"
  resource_constraint:
    action: "Adjust resource requests/limits in values.yaml"
    next: "apply_fix"
  network_issue:
    action: "Investigate network policies and connectivity"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n external-dns --no-headers | grep 'Running'"
    yes: "external_dns_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  external_dns_healthy:
    action: "external-dns-technitium verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# external-dns-technitium cross-service dependencies
service_dependencies:
  external-dns-technitium:
    depends_on:
      - kube-system/cilium
      - traefik/traefik
      - cert-manager/cert-manager
    depended_by:
      - All services requiring DNS records
      - Ingress controllers
      - Certificate management systems
    critical_path: true
    health_check_command: "kubectl get pods -n external-dns --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Technitium DNS server connectivity failures**:

   - **Symptom**: DNS records not being created
   - **Diagnosis**: Check Technitium DNS server connectivity and API status
   - **Resolution**: Verify Technitium DNS server configuration and network connectivity

2. **API authentication errors**:

   - **Symptom**: Authentication failures in logs
   - **Diagnosis**: Check API credentials and Technitium DNS server configuration
   - **Resolution**: Verify API credentials and Technitium DNS server access

3. **DNS record synchronization delays**:

   - **Symptom**: Slow DNS record updates
   - **Diagnosis**: Check Technitium DNS server performance and API response times
   - **Resolution**: Verify Technitium DNS server resources and network latency

4. **Configuration errors**:

   - **Symptom**: ExternalDNS service not starting
   - **Diagnosis**: Check configuration syntax and Technitium DNS server addresses
   - **Resolution**: Verify values.yaml configuration

## Maintenance

### Updates

```bash
# Update external-dns-technitium using Flux
flux reconcile kustomization external-dns-technitium --with-source
```

### Configuration Management

```bash
# Update external-dns-technitium configuration
flux reconcile kustomization external-dns-technitium --with-source

# Verify configuration changes
kubectl logs -n external-dns <pod-name> | grep "configuration"
```

### MCP Integration

- **Library ID**: `external-dns-technitium-dns-management`
- **Version**: `v0.13.5`
- **Usage**: DNS record automation and management
- **Citation**: Use `resolve-library-id` for external-dns configuration and API references

## References

- [ExternalDNS Documentation](https://github.com/kubernetes-sigs/external-dns)
- [Technitium DNS Documentation](https://technitium.com/dns/)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Kubernetes Ingress Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of external-dns-technitium tasks.

### external-dns-technitium Health Check Workflow

```yaml
# external-dns-technitium health check decision tree
start: "check_external_dns_pods"
nodes:
  check_external_dns_pods:
    question: "Are external-dns pods running?"
    command: "kubectl get pods -n external-dns --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_technitium_connectivity"
    no: "restart_external_dns_pods"
  check_technitium_connectivity:
    question: "Can external-dns connect to Technitium?"
    command: "kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=50 | grep -c 'Technitium.*success\\|connected'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "NO_CONNECT"}'' | grep -q ''OK'''
    yes: "check_dns_synchronization"
    no: "fix_technitium_connection"
  check_dns_synchronization:
    question: "Are DNS records being synchronized?"
    command: "kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=50 | grep -c 'record.*created\\|record.*updated'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "NO_SYNC"}'' | grep -q ''OK'''
    yes: "external_dns_healthy"
    no: "fix_dns_sync"
  restart_external_dns_pods:
    action: "Restart external-dns pods"
    next: "check_external_dns_pods"
  fix_technitium_connection:
    action: "Check Technitium server connectivity and API credentials"
    next: "check_technitium_connectivity"
  fix_dns_sync:
    action: "Check DNS record sources and synchronization configuration"
    next: "check_dns_synchronization"
  external_dns_healthy:
    action: "External-DNS Technitium service is healthy and synchronizing"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for external-dns-technitium documentation.
- Confirm the catalog entry contains the documentation or API details needed for external-dns-technitium operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers external-dns-technitium documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed external-dns-technitium configuration changes.

### When external-dns-technitium documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in external-dns-technitium change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting external-dns-technitium documentation.
