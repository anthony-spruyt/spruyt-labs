# reloader - Configuration Reloader

## Overview

Reloader is a Kubernetes controller that automatically reloads configurations when ConfigMaps or Secrets are updated. It monitors changes to configuration resources and triggers pod restarts or rolling updates to ensure applications use the latest configuration in the spruyt-labs homelab infrastructure.

## Directory Layout

```yaml
reloader/
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
- Applications that need automatic configuration reloading
- Proper RBAC permissions for reloader to monitor resources
- ConfigMaps and Secrets that need to be watched

## Operation

### Procedures

1. **Configuration monitoring**:

   ```bash
   # Check reloader service status
   kubectl get pods -n reloader

   # Verify watched resources
   kubectl logs -n reloader <pod-name> | grep "watching"

   # Check reloading events
   kubectl get events -n reloader
   ```

2. **Annotation management**:

   ```bash
   # Add new annotation to deployment
   kubectl annotate deployment <deployment-name> \
     secret.reloader.stakater.com/reload="<secret-name>"

   # Verify annotations
   kubectl get deployment <deployment-name> -o json | jq '.metadata.annotations'
   ```

### Decision Trees

```yaml
# reloader operational decision tree
start: "reloader_health_check"
nodes:
  reloader_health_check:
    question: "Is reloader healthy?"
    command: "kubectl get pods -n reloader --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "reloader_healthy"
  investigate_issue:
    action: "kubectl describe pods -n reloader | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      rbac_permission: "RBAC permission issue"
      config_error: "Configuration mismatch"
      resource_constraint: "Resource limitation"
      network_issue: "Network connectivity"
  rbac_permission:
    action: "Check RBAC permissions: kubectl get clusterroles,clusterrolebindings | grep reloader"
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
    command: "kubectl get pods -n reloader --no-headers | grep 'Running'"
    yes: "reloader_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  reloader_healthy:
    action: "reloader verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# reloader cross-service dependencies
service_dependencies:
  reloader:
    depends_on:
      - kube-system/cilium
    depended_by:
      - All applications using ConfigMaps/Secrets
      - All services requiring dynamic configuration
      - All workloads needing auto-reloading
    critical_path: true
    health_check_command: "kubectl get pods -n reloader --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **RBAC permission errors**:

   - **Symptom**: Reloader unable to watch resources
   - **Diagnosis**: Check RBAC permissions and service accounts
   - **Resolution**: Verify cluster roles and role bindings

2. **Configuration reloading failures**:

   - **Symptom**: Pods not restarting after config changes
   - **Diagnosis**: Check reloader logs and annotations
   - **Resolution**: Verify annotation syntax and resource names

3. **Resource constraints**:

   - **Symptom**: Pods in Pending state or frequent restarts
   - **Diagnosis**: Check resource requests vs available cluster resources
   - **Resolution**: Adjust resource limits or scale cluster

4. **Event processing delays**:

   - **Symptom**: Slow configuration reloading
   - **Diagnosis**: Check reloader performance and event queue
   - **Resolution**: Verify reloader resources and event processing

## Maintenance

### Updates

```bash
# Update reloader using Flux
flux reconcile kustomization reloader --with-source
```

### Annotation Management

```bash
# Add new reloader annotation
kubectl annotate deployment <deployment-name> \
  configmap.reloader.stakater.com/reload="<configmap-name>"

# Remove reloader annotation
kubectl annotate deployment <deployment-name> \
  configmap.reloader.stakater.com/reload-
```

### MCP Integration

- **Library ID**: `reloader-configuration-management`
- **Version**: `v1.0.70`
- **Usage**: Automatic configuration reloading and management
- **Citation**: Use `resolve-library-id` for reloader configuration and API references

## References

- [Reloader Documentation](https://github.com/stakater/Reloader)
- [Reloader Helm Chart](https://github.com/stakater/Reloader/tree/master/deployments/kubernetes/chart/reloader)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Kubernetes ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of reloader tasks.

### reloader Health Check Workflow

```yaml
# reloader health check decision tree
start: "check_reloader_pods"
nodes:
  check_reloader_pods:
    question: "Are reloader pods running?"
    command: "kubectl get pods -n reloader --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_resource_watching"
    no: "restart_reloader_pods"
  check_resource_watching:
    question: "Is reloader watching resources?"
    command: "kubectl logs -n reloader -l app.kubernetes.io/name=reloader --tail=20 | grep -c 'watching\\|monitoring'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "NOT_WATCHING"}'' | grep -q ''OK'''
    yes: "check_event_processing"
    no: "fix_resource_watching"
  check_event_processing:
    question: "Is reloader processing events?"
    command: "kubectl logs -n reloader -l app.kubernetes.io/name=reloader --tail=20 | grep -c 'reloading\\|triggered\\|restarted'"
    validation: 'awk ''{if ($1 >= 0) print "OK"; else print "NO_EVENTS"}'' | grep -q ''OK'''
    yes: "reloader_healthy"
    no: "fix_event_processing"
  restart_reloader_pods:
    action: "Restart reloader pods"
    next: "check_reloader_pods"
  fix_resource_watching:
    action: "Check RBAC permissions and resource access"
    next: "check_resource_watching"
  fix_event_processing:
    action: "Check event processing and annotation configuration"
    next: "check_event_processing"
  reloader_healthy:
    action: "Reloader configuration management is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for reloader documentation.
- Confirm the catalog entry contains the documentation or API details needed for reloader operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers reloader documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed reloader configuration changes.

### When reloader documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in reloader change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting reloader documentation.
