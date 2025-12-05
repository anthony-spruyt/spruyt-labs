# irq-balance-ms-01 - IRQ Balancing for Management Server

## Overview

IRQ Balance is a Linux daemon that distributes hardware interrupts across multiple CPUs to improve system performance. The ms-01 variant is specifically configured for the management server in the spruyt-labs homelab infrastructure, ensuring optimal interrupt handling for management workloads.

## Directory Layout

```yaml
irq-balance-ms-01/
├── app/
│   ├── kustomization.yaml            # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Prerequisites

- Kubernetes cluster with proper node access
- Management server (ms-01) with appropriate CPU configuration
- Proper kernel support for IRQ balancing
- Network connectivity for node management

## Operation

### Procedures

1. **IRQ balancing monitoring**:

```bash
# Check irq-balance service status
kubectl get pods -n irq-balance

# Verify IRQ balancing
kubectl exec -n irq-balance <pod-name> -- systemctl status irqbalance

# Check IRQ distribution
kubectl exec -n irq-balance <pod-name> -- cat /proc/interrupts
```

2. **Configuration management**:

```bash
# Check current configuration
kubectl exec -n irq-balance <pod-name> -- cat /etc/default/irqbalance

# Verify IRQ balance configuration
kubectl exec -n irq-balance <pod-name> -- irqbalance --debug
```

3. **Performance monitoring**:

```bash
# Check IRQ balancing status
kubectl exec -n irq-balance <pod-name> -- systemctl status irqbalance

# Monitor IRQ distribution
kubectl exec -n irq-balance <pod-name> -- watch -n 1 cat /proc/interrupts
```

### Decision Trees

```yaml
# irq-balance-ms-01 operational decision tree
start: "irq_balance_health_check"
nodes:
  irq_balance_health_check:
    question: "Is irq-balance-ms-01 healthy?"
    command: "kubectl get pods -n irq-balance --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "irq_balance_healthy"
  investigate_issue:
    action: "kubectl describe pods -n irq-balance | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      node_access: "Node access problem"
      config_error: "Configuration mismatch"
      resource_constraint: "Resource limitation"
      kernel_issue: "Kernel support issue"
  node_access:
    action: "Check node access: kubectl get nodes | grep ms-01"
    next: "apply_fix"
  config_error:
    action: "Review values.yaml and Helm configuration"
    next: "apply_fix"
  resource_constraint:
    action: "Adjust resource requests/limits in values.yaml"
    next: "apply_fix"
  kernel_issue:
    action: "Verify kernel IRQ balancing support"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n irq-balance --no-headers | grep 'Running'"
    yes: "irq_balance_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  irq_balance_healthy:
    action: "irq-balance-ms-01 verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# irq-balance-ms-01 cross-service dependencies
service_dependencies:
  irq-balance-ms-01:
    depends_on:
      - kube-system/cilium
    depended_by:
      - Management workloads
      - Monitoring systems
      - Control plane components
    critical_path: true
    health_check_command: "kubectl get pods -n irq-balance --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Node access problems**:

   - **Symptom**: Pod unable to access management server
   - **Diagnosis**: Check node status and access permissions
   - **Resolution**: Verify node labels and taints

2. **IRQ balancing not working**:

   - **Symptom**: Uneven IRQ distribution
   - **Diagnosis**: Check IRQ balance configuration and kernel support
   - **Resolution**: Verify IRQ balance parameters and kernel modules

3. **Resource constraints**:

   - **Symptom**: Pods in Pending state or frequent restarts
   - **Diagnosis**: Check resource requests vs available cluster resources
   - **Resolution**: Adjust resource limits or scale cluster

4. **Configuration errors**:

   - **Symptom**: IRQ balance service not starting
   - **Diagnosis**: Check configuration syntax and parameters
   - **Resolution**: Verify values.yaml configuration

## Maintenance

### Updates

```bash
# Update irq-balance-ms-01 using Flux
flux reconcile kustomization irq-balance-ms-01 --with-source
```

### Configuration Management

```bash
# Update irq-balance-ms-01 configuration
flux reconcile kustomization irq-balance-ms-01 --with-source

# Verify configuration changes
kubectl exec -n irq-balance <pod-name> -- cat /etc/default/irqbalance
```

### MCP Integration

- **Library ID**: `irq-balance-management-interrupt-management`
- **Version**: `v1.9.0`
- **Usage**: IRQ balancing and interrupt distribution for management servers
- **Citation**: Use `resolve-library-id` for irq-balance configuration and API references

## References

- [IRQ Balance Documentation](https://github.com/irqbalance/irqbalance)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Kubernetes Node Management](https://kubernetes.io/docs/concepts/architecture/nodes/)

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of irq-balance-ms-01 tasks.

### irq-balance-ms-01 Health Check Workflow

```yaml
# irq-balance-ms-01 health check decision tree
start: "check_irq_balance_ms01_pods"
nodes:
  check_irq_balance_ms01_pods:
    question: "Are irq-balance pods running?"
    command: "kubectl get pods -n irq-balance --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_irqbalance_ms01_service"
    no: "restart_irq_balance_ms01_pods"
  check_irqbalance_ms01_service:
    question: "Is irqbalance service running?"
    command: "kubectl exec -n irq-balance deployment/irq-balance-ms-01 -- systemctl is-active irqbalance | grep -c 'active'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "SERVICE_FAIL"}'' | grep -q ''OK'''
    yes: "check_irq_ms01_distribution"
    no: "start_irqbalance_ms01_service"
  check_irq_ms01_distribution:
    question: "Are IRQs being distributed?"
    command: "kubectl exec -n irq-balance deployment/irq-balance-ms-01 -- cat /proc/interrupts | grep -c 'CPU[0-9]'"
    validation: 'awk ''{if ($1 >= 2) print "OK"; else print "DISTRIBUTION_FAIL"}'' | grep -q ''OK'''
    yes: "irq_balance_ms01_healthy"
    no: "fix_irq_ms01_distribution"
  restart_irq_balance_ms01_pods:
    action: "Restart irq-balance pods"
    next: "check_irq_balance_ms01_pods"
  start_irqbalance_ms01_service:
    action: "Start irqbalance service"
    next: "check_irqbalance_ms01_service"
  fix_irq_ms01_distribution:
    action: "Check IRQ balancing configuration and kernel support"
    next: "check_irq_ms01_distribution"
  irq_balance_ms01_healthy:
    action: "IRQ balancing for management server ms-01 is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for irq-balance-ms-01 documentation.
- Confirm the catalog entry contains the documentation or API details needed for irq-balance-ms-01 operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers irq-balance-ms-01 documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed irq-balance-ms-01 configuration changes.

### When irq-balance-ms-01 documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in irq-balance-ms-01 change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting irq-balance-ms-01 documentation.
