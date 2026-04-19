# Victoria Metrics k8s Stack

## Summary

Victoria Metrics k8s stack provides comprehensive monitoring, alerting, and visualization capabilities for the spruyt-labs Kubernetes cluster. This component is critical for observability and operational awareness.

## Preconditions

- Kubernetes cluster operational with FluxCD reconciliation active
- victoria-metrics-operator (dependsOn)
- external-secrets (dependsOn)
- authentik (dependsOn)
- Storage class configured for persistent volume claims
- Network connectivity between observability namespace and other cluster components
- Appropriate RBAC permissions for service accounts

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
# Verify VMSingle status (CRD-managed, not a vanilla Deployment)
kubectl get vmsingle -n observability victoria-metrics-k8s-stack -o jsonpath='{.status.updateStatus}'

# Verify all pods running
kubectl get pods -n observability --selector=app.kubernetes.io/name=vmsingle

# Test metrics endpoint
kubectl exec -n observability <victoria-metrics-pod> -- curl -s "http://localhost:8428/api/v1/query?query=up"

# Check alertmanager secret exists
kubectl get secret -n observability victoria-metrics-k8s-stack-alertmanager
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

## References

- [VictoriaMetrics Official Documentation](https://docs.victoriametrics.com/)
- [Helm Chart Reference](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-metrics-k8s-stack)
- [Prometheus Compatibility Guide](https://docs.victoriametrics.com/#prometheus-compatibility)
- [Alertmanager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)

## Change History

- **2025-12-04**: Initial documentation created as part of documentation maintenance workflow
