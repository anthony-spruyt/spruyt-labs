# Spegel - Local Container Registry Mirror

## Overview

Spegel is a local container registry mirror that caches and serves container images within the Kubernetes cluster. In the spruyt-labs homelab infrastructure, Spegel reduces external network dependencies and improves image pull performance by serving frequently used images locally.

## Directory Layout

```yaml
spegel/
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
- Sufficient storage for cached container images
- Network connectivity for registry operations
- Proper RBAC permissions for image operations
- Container runtime with registry support

## Operation

### Procedures

1. **Image caching management**:

   ```bash
   # Check cached images
   kubectl exec -it <spegel-pod> -n spegel -- spegel list

   # Monitor cache performance
   kubectl logs -n spegel <spegel-pod> | grep "cache"
   ```

2. **Registry operations**:

   ```bash
   # Check registry health
   kubectl exec -it <spegel-pod> -n spegel -- spegel health

   # Monitor pull operations
   kubectl logs -n spegel <spegel-pod> | grep "pull"
   ```

3. **Configuration updates**:

   ```bash
   # Update Spegel configuration
   kubectl apply -f values.yaml

   # Restart pods for configuration changes
   kubectl rollout restart deployment spegel -n spegel
   ```

### Decision Trees

```yaml
# Spegel operational decision tree
start: "spegel_health_check"
nodes:
  spegel_health_check:
    question: "Is Spegel healthy?"
    command: "kubectl get pods -n spegel --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "spegel_healthy"
  investigate_issue:
    action: "kubectl describe pods -n spegel | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      storage_issue: "Storage capacity or permission problem"
      network_connectivity: "Network connectivity issue"
      cache_corruption: "Cache corruption or inconsistency"
      configuration_error: "Configuration mismatch"
  storage_issue:
    action: "Check storage usage: kubectl get pvc -n spegel"
    next: "apply_fix"
  network_connectivity:
    action: "Test network connectivity: kubectl exec -it <test-pod> -n spegel -- curl -v http://spegel:5000"
    next: "apply_fix"
  cache_corruption:
    action: "Check cache integrity: kubectl exec -it <spegel-pod> -n spegel -- spegel verify"
    next: "apply_fix"
  configuration_error:
    action: "Review values.yaml and registry configuration"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n spegel --no-headers | grep 'Running'"
    yes: "spegel_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  spegel_healthy:
    action: "Spegel verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# Spegel cross-service dependencies
service_dependencies:
  spegel:
    depends_on:
      - kube-system/cilium
      - observability/victoria-metrics-k8s-stack
      - rook-ceph/rook-ceph
    depended_by:
      - All workloads using container images
      - All pods pulling images from registry
      - All CI/CD pipelines
    critical_path: true
    health_check_command: "kubectl get pods -n spegel --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Cache consistency problems**:

   - **Symptom**: Inconsistent image availability
   - **Diagnosis**: Check cache verification logs
   - **Resolution**: Clear and rebuild cache

2. **Storage capacity issues**:

   - **Symptom**: Cache eviction or storage errors
   - **Diagnosis**: Monitor storage usage
   - **Resolution**: Scale storage or clean up unused images

3. **Network connectivity problems**:

   - **Symptom**: Image pull failures
   - **Diagnosis**: Test network connectivity
   - **Resolution**: Verify network policies and DNS

4. **Authentication failures**:

   - **Symptom**: Registry authentication errors
   - **Diagnosis**: Check authentication configuration
   - **Resolution**: Verify credentials and RBAC policies

## Maintenance

### Updates

```bash
# Update Spegel using Flux
flux reconcile kustomization spegel --with-source

# Check update status
kubectl get helmreleases -n spegel
```

### Cache Management

```bash
# Clear cache
kubectl exec -it <spegel-pod> -n spegel -- spegel clear

# Rebuild cache
kubectl exec -it <spegel-pod> -n spegel -- spegel rebuild
```

### MCP Integration

- **Library ID**: `spegel-container-registry`
- **Version**: `v0.0.20`
- **Usage**: Local container registry mirror
- **Citation**: Use `resolve-library-id` for Spegel configuration

## References

- [Spegel Documentation](https://github.com/XenitAB/spegel)
- [Container Registry Specification](https://github.com/opencontainers/distribution-spec)
- [Kubernetes Image Pull Secrets](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)
- [Registry Performance Tuning](https://docs.docker.com/registry/)

## Agent-Friendly Workflows

### Spegel Health Check Workflow

```yaml
# Spegel health check decision tree
start: "check_spegel_pods"
nodes:
  check_spegel_pods:
    question: "Are Spegel pods running?"
    command: "kubectl get pods -n spegel --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_registry_api"
    no: "restart_spegel_pods"
  check_registry_api:
    question: "Is Spegel registry API responding?"
    command: "kubectl exec -n spegel deployment/spegel -- curl -s http://localhost:5000/v2/ | grep -c '{}'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "API_FAIL"}'' | grep -q ''OK'''
    yes: "check_image_caching"
    no: "fix_registry_api"
  check_image_caching:
    question: "Is image caching working?"
    command: "kubectl logs -n spegel -l app.kubernetes.io/name=spegel --tail=20 | grep -c 'cached\\|mirror'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "CACHE_FAIL"}'' | grep -q ''OK'''
    yes: "spegel_healthy"
    no: "fix_image_caching"
  restart_spegel_pods:
    action: "Restart Spegel pods"
    next: "check_spegel_pods"
  fix_registry_api:
    action: "Check Spegel registry configuration and ports"
    next: "check_registry_api"
  fix_image_caching:
    action: "Check storage and mirror configuration"
    next: "check_image_caching"
  spegel_healthy:
    action: "Spegel container registry mirror is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for Spegel documentation.
- Confirm the catalog entry contains the documentation or API details needed for Spegel operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers Spegel documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed Spegel configuration changes.

### When Spegel documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in Spegel change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting Spegel documentation.
