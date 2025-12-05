# Victoria Metrics k8s Stack

## Summary

Victoria Metrics k8s stack provides comprehensive monitoring, alerting, and visualization capabilities for the spruyt-labs Kubernetes cluster. This component is critical for observability and operational awareness.

## Preconditions

- Kubernetes cluster operational with FluxCD reconciliation active
- Storage class configured for persistent volume claims
- Network connectivity between observability namespace and other cluster components
- Appropriate RBAC permissions for service accounts

## Directory Layout

```yaml
victoria-metrics-k8s-stack/
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
# Check VictoriaMetrics health
kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-k8s-stack

# Verify data ingestion
kubectl exec -n observability <victoria-metrics-pod> -- curl -s http://localhost:8428/api/v1/status

# Check alertmanager status
kubectl get pods -n observability --selector=app.kubernetes.io/component=alertmanager

# Monitor resource usage
kubectl top pods -n observability
```

### Cross-Service Dependencies

```yaml
service_dependencies:
  victoria-metrics-k8s-stack:
    depends_on:
      - rook-ceph-storage
      - cilium-networking
      - cert-manager
    depended_by:
      - grafana-dashboards
      - cluster-monitoring
      - application-services
    critical_path: true
    health_check_command: "kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-k8s-stack --no-headers | grep -c 'Running'"
```

## Troubleshooting

### Common Issues

#### Symptom: VictoriaMetrics pods not starting

**Diagnosis**:

- Check resource constraints with `kubectl describe pod <pod-name> -n observability`
- Verify storage availability with `kubectl get pvc -n observability`
- Review Helm values for incorrect configuration

**Resolution**:

1. Adjust resource requests/limits in values.yaml
2. Verify storage class and PVC configuration
3. Check chart version compatibility

#### Symptom: No data appearing in metrics

**Diagnosis**:

- Verify service discovery configuration
- Check scrape targets with `kubectl exec -n observability <pod> -- curl http://localhost:8428/api/v1/targets`
- Review network policies and connectivity

**Resolution**:

1. Validate service monitor configurations
2. Check Cilium network policies for observability namespace
3. Verify service endpoints are correctly annotated

## Validation

### Expected Outcomes

1. **Deployment Success**: All VictoriaMetrics pods show `Running` status
2. **Data Ingestion**: Metrics appear in VictoriaMetrics UI within 5 minutes
3. **Alerting Functional**: Alertmanager shows ready status and can send test alerts
4. **Resource Usage**: CPU/Memory within defined limits (check with `kubectl top pods`)

### Validation Commands

```bash
# Verify deployment status
kubectl get deployment -n observability victoria-metrics-k8s-stack -o json | jq '.status.availableReplicas'

# Test metrics endpoint
kubectl exec -n observability <victoria-metrics-pod> -- curl -s "http://localhost:8428/api/v1/query?query=up"

# Check alertmanager configuration
kubectl get secret -n observability victoria-metrics-k8s-stack-alertmanager -o yaml
```

## Escalation

- **Monitoring Issues**: Contact observability team via #monitoring channel
- **Storage Problems**: Escalate to storage team for Rook Ceph issues
- **Network Connectivity**: Engage networking team for Cilium troubleshooting
- **Chart Configuration**: Review with Helm maintainers for values.yaml questions

## Maintenance

### Updates

1. Review upstream chart changes before updating
2. Test new versions in staging environment first
3. Update values.yaml to maintain compatibility

### Backups

1. VictoriaMetrics data is stored in Rook Ceph PVCs
2. Regular snapshots are handled by Velero backup system
3. Verify backup status with `velero get backups`

### MCP Integration

```yaml
# Context7 library usage for VictoriaMetrics documentation
context7_usage:
  library_id: "victoria-metrics-k8s-stack"
  version: "v0.12.0"
  source: "VictoriaMetrics official documentation"
  retrieved_at: "2025-12-04"
  used_for: "Helm chart configuration and operational procedures"
```

## References

- [VictoriaMetrics Official Documentation](https://docs.victoriametrics.com/)
- [Helm Chart Reference](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-metrics-k8s-stack)
- [Prometheus Compatibility Guide](https://docs.victoriametrics.com/#prometheus-compatibility)
- [Alertmanager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)

## Decision Tree for Operational Workflow

```yaml
start: "victoria_metrics_health_check"
nodes:
  victoria_metrics_health_check:
    question: "Is VictoriaMetrics k8s stack healthy?"
    command: "kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-k8s-stack --no-headers | grep -v 'Running'"
    validation: "wc -l | grep -q '^0$'"
    yes: "component_healthy"
    no: "investigate_issue"
  investigate_issue:
    action: "kubectl describe pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-k8s-stack"
    log_command: "kubectl logs -n observability <pod-name> --tail=50"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    diagnostic_commands:
      - "kubectl get events -n observability --sort-by=.metadata.creationTimestamp | tail -10"
      - "kubectl get pvc -n observability"
      - "kubectl top pods -n observability"
    options:
      resource_constraint: "Resource limits exceeded"
      storage_issue: "PVC binding or storage problems"
      configuration_error: "Helm values misconfiguration"
      network_problem: "Connectivity or service discovery issues"
  resource_constraint:
    action: "Adjust resource requests/limits in values.yaml"
    commands:
      - "kubectl top pods -n observability"
      - "kubectl describe nodes | grep -A 10 'Capacity'"
    next: "apply_fix"
  storage_issue:
    action: "Verify storage class and PVC configuration"
    commands:
      - "kubectl get pvc -n observability -o wide"
      - "kubectl describe pvc -n observability <pvc-name>"
    next: "apply_fix"
  configuration_error:
    action: "Review and correct Helm values"
    commands:
      - "helm get values victoria-metrics-k8s-stack -n observability"
      - "kubectl get cm -n observability -o yaml"
    next: "apply_fix"
  network_problem:
    action: "Check network policies and service connectivity"
    commands:
      - "kubectl get networkpolicy -n observability"
      - "kubectl get endpoints -n observability"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation based on root cause"
    validation_commands:
      - "kubectl apply -f <corrected-config>"
      - "kubectl rollout restart deployment victoria-metrics-k8s-stack -n observability"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-k8s-stack --no-headers | grep 'Running'"
    validation: "wc -l | grep -q '^[1-9]'"
    yes: "component_healthy"
    no: "escalate_issue"
  escalate_issue:
    action: "Escalate with comprehensive diagnostics to observability team"
    next: "end"
  component_healthy:
    action: "VictoriaMetrics k8s stack verified healthy"
    next: "end"
end: "end"
```

## Change History

- **2025-12-04**: Initial documentation created as part of documentation maintenance workflow
- **Documentation Standards**: Follows spruyt-labs README template and decision tree requirements
- **Validation**: Passes `task dev-env:lint` requirements
