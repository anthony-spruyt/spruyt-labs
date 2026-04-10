# Victoria Logs Single

## Summary

Victoria Logs Single provides centralized log collection and storage for the spruyt-labs Kubernetes cluster, enabling comprehensive log analysis and troubleshooting capabilities.

## Preconditions

- Kubernetes cluster with FluxCD reconciliation active
- Persistent storage available for log retention
- Network connectivity between observability namespace and application pods
- Appropriate RBAC for log collection service accounts

## Operation

### Monitoring Commands

```bash
# Check Victoria Logs health
kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-logs-single

# Verify log ingestion
kubectl exec -n observability <victoria-logs-pod> -- curl -s http://localhost:9428/api/v1/status

# Check storage usage
kubectl exec -n observability <victoria-logs-pod> -- df -h

# Monitor resource usage
kubectl top pods -n observability --selector=app.kubernetes.io/name=victoria-logs-single
```

## Troubleshooting

### Common Issues

#### Symptom: Logs not appearing in Victoria Logs

**Diagnosis**:

- Verify the separate vector deployment is running and collecting logs
- Check log collection annotations on application pods
- Review network policies for observability namespace

**Resolution**:

1. Add required annotations to application deployments
2. Verify the vector deployment status in the observability namespace
3. Check Cilium network policies for log collection traffic

#### Symptom: High storage usage or retention issues

**Diagnosis**:

- Check current storage usage with `kubectl exec -n observability <pod> -- df -h`
- Review retention settings in values.yaml
- Verify PVC size and storage class configuration

**Resolution**:

1. Adjust retention periods in Helm values
2. Increase PVC size if needed
3. Configure log rotation and compression settings

## Validation

### Expected Outcomes

1. **Deployment Success**: Victoria Logs pod shows `Running` status
2. **Log Ingestion**: Application logs appear in Victoria Logs UI within 2 minutes
3. **Storage Management**: Log retention works as configured
4. **Resource Usage**: CPU under 1000m, Memory under 2Gi for normal operation

### Validation Commands

```bash
# Verify deployment status
kubectl get deployment -n observability victoria-logs-single -o json | jq '.status.availableReplicas'

# Test log ingestion endpoint
kubectl exec -n observability <victoria-logs-pod> -- curl -s "http://localhost:9428/api/v1/query?query={job=~\"kubernetes.*\"}"

# Check storage metrics
kubectl exec -n observability <victoria-logs-pod> -- curl -s "http://localhost:9428/api/v1/status" | jq '.storage'
```

## Escalation

- **Storage Issues**: Contact storage team for Rook Ceph configuration
- **Log Collection Problems**: Engage application teams for sidecar configuration
- **Performance Tuning**: Consult observability team for optimization
- **Network Connectivity**: Escalate to networking team for Cilium troubleshooting

## Maintenance

### Updates

1. Review log schema changes in new versions
2. Test retention and compression settings
3. Update sidecar configurations for application changes

### Backups

1. Log data stored in Rook Ceph PVCs
2. Configuration backed up via Velero
3. Verify backup status: `velero get backups | grep observability`

## References

- [Victoria Logs Documentation](https://docs.victoriametrics.com/VictoriaLogs/)
- [Helm Chart Reference](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-logs-single)
- [Log Collection Guide](https://docs.victoriametrics.com/victorialogs/vlagent/)

## Change History

- **2025-12-04**: Initial documentation created during documentation maintenance workflow
