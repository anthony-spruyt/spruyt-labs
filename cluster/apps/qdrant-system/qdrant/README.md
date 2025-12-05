# Qdrant - Vector Search Engine

## Overview

Qdrant is a high-performance vector similarity search engine and vector database. In the spruyt-labs homelab infrastructure, Qdrant provides advanced vector search capabilities for AI/ML applications, semantic search, and recommendation systems.

## Directory Layout

```yaml
qdrant/
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
- Sufficient storage for vector data
- Network connectivity for search operations
- Proper resource allocation for vector computations
- Monitoring for performance metrics

### Validation

```bash
# Check Qdrant pods are running
kubectl get pods -n qdrant-system --no-headers | grep 'Running'

# Verify service endpoints
kubectl get endpoints -n qdrant-system

# Test Qdrant API connectivity
kubectl exec -it <test-pod> -n qdrant-system -- curl -v http://qdrant.qdrant-system.svc.cluster.local:6333
```

## Operation

### Procedures

1. **Collection management**:

   ```bash
   # List collections
   kubectl exec -it <qdrant-pod> -n qdrant-system -- curl -X GET http://localhost:6333/collections

   # Monitor collection performance
   kubectl logs -n qdrant-system <qdrant-pod> | grep "collection"
   ```

2. **Search operations**:

   ```bash
   # Check search performance
   kubectl exec -it <qdrant-pod> -n qdrant-system -- curl -X POST http://localhost:6333/collections/<collection>/points/search

   # Monitor query metrics
   kubectl logs -n qdrant-system <qdrant-pod> | grep "search"
   ```

3. **Configuration updates**:

   ```bash
   # Update Qdrant configuration
   kubectl apply -f values.yaml

   # Restart pods for configuration changes
   kubectl rollout restart statefulset qdrant -n qdrant-system
   ```

### Decision Trees

```yaml
# Qdrant operational decision tree
start: "qdrant_health_check"
nodes:
  qdrant_health_check:
    question: "Is Qdrant healthy?"
    command: "kubectl get pods -n qdrant-system --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "qdrant_healthy"
  investigate_issue:
    action: "kubectl describe pods -n qdrant-system | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      storage_issue: "Storage capacity or performance problem"
      memory_pressure: "Memory pressure or allocation issue"
      network_connectivity: "Network connectivity problem"
      configuration_error: "Configuration mismatch"
  storage_issue:
    action: "Check storage usage: kubectl get pvc -n qdrant-system"
    next: "apply_fix"
  memory_pressure:
    action: "Check memory usage: kubectl top pods -n qdrant-system"
    next: "apply_fix"
  network_connectivity:
    action: "Test network connectivity: kubectl exec -it <test-pod> -n qdrant-system -- curl -v http://qdrant:6333"
    next: "apply_fix"
  configuration_error:
    action: "Review values.yaml and Qdrant configuration"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n qdrant-system --no-headers | grep 'Running'"
    yes: "qdrant_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  qdrant_healthy:
    action: "Qdrant verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# Qdrant cross-service dependencies
service_dependencies:
  qdrant:
    depends_on:
      - kube-system/cilium
      - observability/victoria-metrics-k8s-stack
      - rook-ceph/rook-ceph
    depended_by:
      - AI/ML applications using vector search
      - Semantic search services
      - Recommendation engines
    critical_path: false
    health_check_command: "kubectl get pods -n qdrant-system --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Vector indexing problems**:

   - **Symptom**: Slow or failed vector indexing
   - **Diagnosis**: Check indexing logs and performance
   - **Resolution**: Optimize vector dimensions or scale resources

2. **Search performance issues**:

   - **Symptom**: High latency search queries
   - **Diagnosis**: Monitor search metrics and query patterns
   - **Resolution**: Optimize search parameters or scale cluster

3. **Storage capacity problems**:

   - **Symptom**: Storage full or write errors
   - **Diagnosis**: Check storage usage and capacity
   - **Resolution**: Scale storage or clean up old collections

4. **Network connectivity failures**:

   - **Symptom**: API connection timeouts
   - **Diagnosis**: Test network connectivity and DNS
   - **Resolution**: Verify network policies and service discovery

## Maintenance

### Updates

```bash
# Update Qdrant using Flux
flux reconcile kustomization qdrant --with-source

# Check update status
kubectl get helmreleases -n qdrant-system
```

### Collection Management

```bash
# Create new collection
kubectl exec -it <qdrant-pod> -n qdrant-system -- curl -X PUT http://localhost:6333/collections/<collection> -H "Content-Type: application/json" -d '{"vectors": {"size": 128, "distance": "Cosine"}}'

# Delete collection
kubectl exec -it <qdrant-pod> -n qdrant-system -- curl -X DELETE http://localhost:6333/collections/<collection>
```

### MCP Integration

- **Library ID**: `qdrant-vector-search`
- **Version**: `v1.7.0`
- **Usage**: Vector similarity search engine
- **Citation**: Use `resolve-library-id` for Qdrant configuration

## References

- [Qdrant Documentation](https://qdrant.tech/documentation/)
- [Qdrant GitHub](https://github.com/qdrant/qdrant)
- [Vector Search Guide](https://qdrant.tech/documentation/guides/)
- [Kubernetes Stateful Applications](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)

## Agent-Friendly Workflows

### Qdrant Health Check Workflow

```yaml
# Qdrant health check decision tree
start: "check_qdrant_pods"
nodes:
  check_qdrant_pods:
    question: "Are Qdrant pods running?"
    command: "kubectl get pods -n qdrant-system --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_qdrant_api"
    no: "restart_qdrant_pods"
  check_qdrant_api:
    question: "Is Qdrant API responding?"
    command: "kubectl exec -n qdrant-system deployment/qdrant -- curl -s http://localhost:6333/health | grep -c 'true'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "API_FAIL"}'' | grep -q ''OK'''
    yes: "check_collections"
    no: "fix_api_connectivity"
  check_collections:
    question: "Can Qdrant access collections?"
    command: "kubectl exec -n qdrant-system deployment/qdrant -- curl -s http://localhost:6333/collections | jq -r '.result.collections | length' 2>/dev/null || echo '0'"
    validation: 'awk ''{if ($1 >= 0) print "OK"; else print "COLL_FAIL"}'' | grep -q ''OK'''
    yes: "qdrant_healthy"
    no: "fix_collections"
  restart_qdrant_pods:
    action: "Restart Qdrant pods"
    next: "check_qdrant_pods"
  fix_api_connectivity:
    action: "Check Qdrant API configuration and network connectivity"
    next: "check_qdrant_api"
  fix_collections:
    action: "Check storage and collection configuration"
    next: "check_collections"
  qdrant_healthy:
    action: "Qdrant vector database is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for Qdrant documentation.
- Confirm the catalog entry contains the documentation or API details needed for Qdrant operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers Qdrant documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed Qdrant configuration changes.

### When Qdrant documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in Qdrant change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting Qdrant documentation.
