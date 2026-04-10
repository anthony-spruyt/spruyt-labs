# Qdrant - Vector Search Engine

## Overview

Qdrant is a high-performance vector similarity search engine and vector database. In the spruyt-labs homelab infrastructure, Qdrant provides advanced vector search capabilities for AI/ML applications, semantic search, and recommendation systems.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Sufficient storage for vector data
- Network connectivity for search operations
- Proper resource allocation for vector computations
- Monitoring for performance metrics
- Kyverno deployed (dependency - required for init container policies)

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
   # Edit values.yaml, commit, then: flux reconcile kustomization qdrant --with-source

   # Restart pods for configuration changes
   kubectl rollout restart statefulset qdrant -n qdrant-system
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

## References

- [Qdrant Documentation](https://qdrant.tech/documentation/)
- [Qdrant GitHub](https://github.com/qdrant/qdrant)
- [Vector Search Guide](https://qdrant.tech/documentation/guides/)
- [Kubernetes Stateful Applications](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
