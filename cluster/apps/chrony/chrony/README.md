# chrony - NTP Time Synchronization

## Overview

Chrony is a versatile implementation of the Network Time Protocol (NTP) that provides precise time synchronization for the Kubernetes cluster. It ensures all nodes maintain accurate time, which is critical for distributed systems, logging, authentication, and other time-sensitive operations in the spruyt-labs homelab infrastructure.

## Directory Layout

```yaml
chrony/
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
- Proper network connectivity for NTP servers
- Appropriate firewall rules allowing NTP traffic (UDP port 123)
- Cluster nodes with proper time synchronization requirements

## Operation

### Procedures

1. **Time synchronization monitoring**:

   ```bash
   # Check chrony service status
   kubectl get pods -n chrony

   # Verify time synchronization
   kubectl exec -n chrony <pod-name> -- chronyc tracking

   # Check time sources
   kubectl exec -n chrony <pod-name> -- chronyc sources
   ```

2. **Configuration management**:

   ```bash
   # Check current configuration
   kubectl exec -n chrony <pod-name> -- cat /etc/chrony/chrony.conf

   # Verify NTP server connectivity
   kubectl exec -n chrony <pod-name> -- chronyc ntpdata
   ```

3. **Performance monitoring**:

   ```bash
   # Check time offset and synchronization status
   kubectl exec -n chrony <pod-name> -- chronyc tracking

   # Monitor time sources
   kubectl exec -n chrony <pod-name> -- chronyc sources -v
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate time synchronization monitoring
kubectl get pods -n chrony --no-headers | grep 'Running'

# Expected: At least one pod in Running state

# Validate configuration management
kubectl exec -n chrony <pod-name> -- chronyc tracking

# Expected: Time synchronization status displayed

# Validate performance monitoring
kubectl exec -n chrony <pod-name> -- chronyc sources

# Expected: NTP sources listed with status
```

### Decision Trees

```yaml
# chrony operational decision tree
start: "chrony_health_check"
nodes:
  chrony_health_check:
    question: "Is chrony healthy?"
    command: "kubectl get pods -n chrony --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "chrony_healthy"
  investigate_issue:
    action: "kubectl describe pods -n chrony | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      ntp_connectivity: "NTP server connectivity problem"
      config_error: "Configuration mismatch"
      resource_constraint: "Resource limitation"
      network_issue: "Network connectivity"
  ntp_connectivity:
    action: "Check NTP server connectivity: kubectl exec -n chrony <pod-name> -- chronyc ntpdata"
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
    command: "kubectl get pods -n chrony --no-headers | grep 'Running'"
    yes: "chrony_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  chrony_healthy:
    action: "chrony verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# chrony cross-service dependencies
service_dependencies:
  chrony:
    depends_on:
      - kube-system/cilium
    depended_by:
      - All cluster nodes requiring time synchronization
      - All time-sensitive applications
      - Authentication systems
      - Logging and monitoring systems
    critical_path: true
    health_check_command: "kubectl get pods -n chrony --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **NTP server connectivity failures**:

   - **Symptom**: Time synchronization not working
   - **Diagnosis**: Check NTP server connectivity and firewall rules
   - **Resolution**: Verify NTP server addresses and network connectivity

2. **Time drift issues**:

   - **Symptom**: Significant time offset from NTP servers
   - **Diagnosis**: Check chrony tracking and sources
   - **Resolution**: Verify NTP server configuration and network latency

3. **Resource constraints**:

   - **Symptom**: Pods in Pending state or frequent restarts
   - **Diagnosis**: Check resource requests vs available cluster resources
   - **Resolution**: Adjust resource limits or scale cluster

4. **Configuration errors**:

   - **Symptom**: Chrony service not starting
   - **Diagnosis**: Check configuration syntax and NTP server addresses
   - **Resolution**: Verify values.yaml configuration

## Maintenance

### Updates

```bash
# Update chrony using Flux
flux reconcile kustomization chrony --with-source
```

### Configuration Management

```bash
# Update chrony configuration
flux reconcile kustomization chrony --with-source

# Verify configuration changes
kubectl exec -n chrony <pod-name> -- cat /etc/chrony/chrony.conf
```

### MCP Integration

- **Library ID**: `chrony-ntp-time-synchronization`
- **Version**: `v4.2`
- **Usage**: NTP time synchronization and management
- **Citation**: Use `resolve-library-id` for chrony configuration and API references

## References

- [Chrony Documentation](https://chrony.tuxfamily.org/)
- [NTP Protocol Specification](https://tools.ietf.org/html/rfc5905)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Kubernetes Time Synchronization](https://kubernetes.io/docs/concepts/cluster-administration/manage-deployment/)

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of chrony tasks.

### chrony Health Check Workflow

```yaml
# chrony health check decision tree
start: "check_chrony_pods"
nodes:
  check_chrony_pods:
    question: "Are chrony pods running?"
    command: "kubectl get pods -n chrony --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_time_synchronization"
    no: "restart_chrony_pods"
  check_time_synchronization:
    question: "Is time synchronization working?"
    command: 'kubectl exec -n chrony deployment/chrony -- chronyc tracking | grep ''System time'' | awk ''{print $4}'' | sed ''s/s//'' | awk ''{if ($1 < 0.1 && $1 > -0.1) print "OK"; else print "DRIFT"}'' | grep -c ''OK'''
    validation: "grep -q '^1$'"
    yes: "check_ntp_sources"
    no: "fix_time_drift"
  check_ntp_sources:
    question: "Are NTP sources reachable?"
    command: "kubectl exec -n chrony deployment/chrony -- chronyc sources | grep -c '^*'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "NO_SOURCES"}'' | grep -q ''OK'''
    yes: "chrony_healthy"
    no: "fix_ntp_sources"
  restart_chrony_pods:
    action: "Restart chrony pods"
    next: "check_chrony_pods"
  fix_time_drift:
    action: "Check and fix time synchronization issues"
    next: "check_time_synchronization"
  fix_ntp_sources:
    action: "Configure NTP sources and check connectivity"
    next: "check_ntp_sources"
  chrony_healthy:
    action: "chrony time synchronization is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for chrony documentation.
- Confirm the catalog entry contains the documentation or API details needed for chrony operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers chrony documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed chrony configuration changes.

### When chrony documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in chrony change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting chrony documentation.
