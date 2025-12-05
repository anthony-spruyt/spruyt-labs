# Victoria Logs Single

## Summary

Victoria Logs Single provides centralized log collection and storage for the spruyt-labs Kubernetes cluster, enabling comprehensive log analysis and troubleshooting capabilities.

## Preconditions

- Kubernetes cluster with FluxCD reconciliation active
- Persistent storage available for log retention
- Network connectivity between observability namespace and application pods
- Appropriate RBAC for log collection service accounts

## Directory Layout

```yaml
victoria-logs-single/
├── app/
│   ├── kustomization.yaml          # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── persistent-volume-claim.yaml # Storage configuration
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values override
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

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

### Cross-Service Dependencies

```yaml
service_dependencies:
  victoria-logs-single:
    depends_on:
      - rook-ceph-storage
      - cilium-networking
      - victoria-metrics-k8s-stack
    depended_by:
      - application-logging
      - cluster-troubleshooting
      - security-auditing
    critical_path: true
    health_check_command: "kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-logs-single --no-headers | grep -c 'Running'"
```

## Troubleshooting

### Common Issues

#### Symptom: Logs not appearing in Victoria Logs

**Diagnosis**:

- Verify fluent-bit or vector sidecar injection
- Check log collection annotations on application pods
- Review network policies for observability namespace

**Resolution**:

1. Add required annotations to application deployments
2. Verify sidecar container status in application pods
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

### MCP Integration

```yaml
context7_usage:
  library_id: "victoria-logs-single"
  version: "v0.10.0"
  source: "Victoria Logs official documentation"
  retrieved_at: "2025-12-04"
  used_for: "Log collection configuration and operational procedures"
```

## References

- [Victoria Logs Documentation](https://docs.victoriametrics.com/VictoriaLogs/)
- [Helm Chart Reference](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-logs-single)
- [Log Collection Guide](https://docs.victoriametrics.com/victorialogs/vlagent/)

## Decision Tree for Log Management

```yaml
start: "logs_health_check"
nodes:
  logs_health_check:
    question: "Is Victoria Logs single instance healthy?"
    command: "kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-logs-single --no-headers | grep -v 'Running'"
    yes: "investigate_logs"
    no: "logs_healthy"
  investigate_logs:
    action: "kubectl describe pods -n observability --selector=app.kubernetes.io/name=victoria-logs-single"
    log_command: "kubectl logs -n observability -l app.kubernetes.io/name=victoria-logs-single --tail=50"
    next: "analyze_logs_issue"
  analyze_logs_issue:
    question: "What type of logs issue?"
    diagnostic_commands:
      - "kubectl get pvc -n observability | grep victoria-logs"
      - "kubectl exec -n observability <pod> -- df -h"
      - "kubectl get events -n observability | grep victoria-logs"
    options:
      storage_full: "Storage capacity exceeded"
      collection_failed: "Log collection not working"
      performance_issue: "High resource usage or slow queries"
      config_error: "Configuration problem"
  storage_full:
    action: "Check storage usage and retention settings"
    commands:
      - "kubectl exec -n observability <pod> -- df -h"
      - "kubectl get pvc -n observability -o yaml"
    next: "apply_logs_fix"
  collection_failed:
    action: "Verify log collection sidecars and annotations"
    commands:
      - 'kubectl get pods -A -o json | jq ''.items[] | select(.metadata.annotations."logging.victoriametrics.com/enabled" == "true")'''
      - "kubectl describe pods -n <namespace> <app-pod> | grep -A 5 'Containers:'"
    next: "apply_logs_fix"
  performance_issue:
    action: "Optimize resource limits and query performance"
    commands:
      - "kubectl top pods -n observability --selector=app.kubernetes.io/name=victoria-logs-single"
      - "kubectl exec -n observability <pod> -- curl -s 'http://localhost:9428/api/v1/status' | jq '.query_stats'"
    next: "apply_logs_fix"
  config_error:
    action: "Review and correct Helm values configuration"
    commands:
      - "helm get values victoria-logs-single -n observability"
      - "kubectl get cm -n observability -o yaml | grep victoria-logs"
    next: "apply_logs_fix"
  apply_logs_fix:
    action: "Apply appropriate logs remediation"
    validation_commands:
      - "kubectl rollout restart deployment victoria-logs-single -n observability"
      - "kubectl delete pod -n observability -l app.kubernetes.io/name=victoria-logs-single"
    next: "verify_logs_fix"
  verify_logs_fix:
    question: "Is logs issue resolved?"
    command: "kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-logs-single --no-headers | grep 'Running'"
    yes: "logs_healthy"
    no: "escalate_logs_issue"
  escalate_logs_issue:
    action: "Escalate with logs diagnostics and storage metrics to observability team"
    next: "end"
  logs_healthy:
    action: "Victoria Logs single instance verified healthy"
    next: "end"
end: "end"
```

## Change History

- **2025-12-04**: Initial documentation created during documentation maintenance workflow
- **Standards Compliance**: Follows spruyt-labs README template with decision trees
- **Validation**: Designed to pass `task dev-env:lint` requirements
