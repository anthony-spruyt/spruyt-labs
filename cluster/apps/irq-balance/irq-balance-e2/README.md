# irq-balance-e2 - IRQ Balancing

## Overview

IRQ Balance is a Linux daemon that distributes hardware interrupts across multiple CPUs to improve system performance. The e2 variant is specifically configured for the edge node in the spruyt-labs homelab infrastructure, ensuring optimal interrupt handling for network-intensive workloads.

## Directory Layout

```yaml
irq-balance-e2/
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
- Edge node (e2) with appropriate CPU configuration
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
# irq-balance-e2 operational decision tree
start: "irq_balance_health_check"
nodes:
  irq_balance_health_check:
    question: "Is irq-balance-e2 healthy?"
    command: "kubectl get pods -n irq-balance --no-headers | grep -v 'Running'"
    validation: "wc -l | grep -q '^0$'"
    yes: "investigate_issue"
    no: "irq_balance_healthy"
  investigate_issue:
    action: "kubectl describe pods -n irq-balance"
    log_command: "kubectl logs -n irq-balance <pod-name> --tail=50"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    diagnostic_commands:
      - "kubectl get events -n irq-balance --sort-by=.metadata.creationTimestamp | tail -10"
      - "kubectl top pods -n irq-balance"
    options:
      config_error: "Configuration issue"
      dependency_failure: "Dependency problem"
      resource_constraint: "Resource limitation"
  config_error:
    action: "Review values.yaml and Helm configuration"
    commands:
      - "helm get values irq-balance-e2 -n irq-balance"
      - "kubectl get cm -n irq-balance -o yaml"
    next: "apply_fix"
  dependency_failure:
    action: "Check cross-service dependencies"
    commands:
      - "kubectl get nodes | grep e2"
      - "kubectl get pods -n kube-system --selector=k8s-app=cilium"
    next: "apply_fix"
  resource_constraint:
    action: "Adjust resource requests/limits"
    commands:
      - "kubectl top nodes"
      - "kubectl describe nodes | grep -A 10 'Capacity'"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    validation_commands:
      - "kubectl apply -f <fixed-config>"
      - "kubectl rollout restart deployment/<deployment> -n irq-balance"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n irq-balance --no-headers | grep 'Running'"
    validation: "wc -l | grep -q '^[1-9]'"
    yes: "irq_balance_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  irq_balance_healthy:
    action: "irq-balance-e2 verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# irq-balance-e2 cross-service dependencies
service_dependencies:
  irq-balance-e2:
    depends_on:
      - kube-system/cilium
    depended_by:
      - Network-intensive workloads
      - High-performance applications
      - Real-time systems
    critical_path: true
    health_check_command: "kubectl get pods -n irq-balance --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Node access problems**:

   - **Symptom**: Pod unable to access edge node
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
# Update irq-balance-e2 using Flux
flux reconcile kustomization irq-balance-e2 --with-source
```

### Configuration Management

```bash
# Update irq-balance-e2 configuration
flux reconcile kustomization irq-balance-e2 --with-source

# Verify configuration changes
kubectl exec -n irq-balance <pod-name> -- cat /etc/default/irqbalance
```

### MCP Integration

- **Library ID**: `irq-balance-interrupt-management`
- **Version**: `v1.9.0`
- **Usage**: IRQ balancing and interrupt distribution
- **Citation**: Use `resolve-library-id` for irq-balance configuration and API references

## References

- [IRQ Balance Documentation](https://github.com/irqbalance/irqbalance)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Kubernetes Node Management](https://kubernetes.io/docs/concepts/architecture/nodes/)

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of irq-balance-e2 tasks.

### irq-balance-e2 Health Check Workflow

```yaml
# irq-balance-e2 health check decision tree
start: "check_irq_balance_pods"
nodes:
  check_irq_balance_pods:
    question: "Are irq-balance pods running?"
    command: "kubectl get pods -n irq-balance --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_irqbalance_service"
    no: "restart_irq_balance_pods"
  check_irqbalance_service:
    question: "Is irqbalance service running?"
    command: "kubectl exec -n irq-balance deployment/irq-balance-e2 -- systemctl is-active irqbalance | grep -c 'active'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "SERVICE_FAIL"}'' | grep -q ''OK'''
    yes: "check_irq_distribution"
    no: "start_irqbalance_service"
  check_irq_distribution:
    question: "Are IRQs being distributed?"
    command: "kubectl exec -n irq-balance deployment/irq-balance-e2 -- cat /proc/interrupts | grep -c 'CPU[0-9]'"
    validation: 'awk ''{if ($1 >= 2) print "OK"; else print "DISTRIBUTION_FAIL"}'' | grep -q ''OK'''
    yes: "irq_balance_healthy"
    no: "fix_irq_distribution"
  restart_irq_balance_pods:
    action: "Restart irq-balance pods"
    next: "check_irq_balance_pods"
  start_irqbalance_service:
    action: "Start irqbalance service"
    next: "check_irqbalance_service"
  fix_irq_distribution:
    action: "Check IRQ balancing configuration and kernel support"
    next: "check_irq_distribution"
  irq_balance_healthy:
    action: "IRQ balancing for edge node e2 is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for irq-balance-e2 documentation.
- Confirm the catalog entry contains the documentation or API details needed for irq-balance-e2 operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers irq-balance-e2 documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed irq-balance-e2 configuration changes.

### When irq-balance-e2 documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in irq-balance-e2 change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting irq-balance-e2 documentation.
