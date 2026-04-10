# Victoria Metrics Operator

## Summary

Victoria Metrics Operator manages the lifecycle of VictoriaMetrics custom resources, providing automated provisioning, scaling, and management of VictoriaMetrics instances across the cluster.

## Preconditions

- Kubernetes cluster v1.25+ with FluxCD active
- CustomResourceDefinitions for VictoriaMetrics installed
- RBAC permissions configured for operator service account
- Storage classes available for persistent volumes

## Operation

### Monitoring Commands

```bash
# Check operator health
kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-operator

# Verify CRD status
kubectl get crd vmsingles.operator.victoriametrics.com vmagents.operator.victoriametrics.com

# Check operator logs
kubectl logs -n observability -l app.kubernetes.io/name=victoria-metrics-operator --tail=50

# Monitor resource usage
kubectl top pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-operator
```

## Troubleshooting

### Common Issues

#### Symptom: Operator pod crash looping

**Diagnosis**:

- Check operator logs for permission errors
- Verify CRD installation and compatibility
- Review RBAC configuration

**Resolution**:

1. Validate service account permissions
2. Check CRD version compatibility
3. Review operator configuration in values.yaml

#### Symptom: Custom resources not being processed

**Diagnosis**:

- Verify operator is watching correct namespaces
- Check custom resource annotations and labels
- Review operator log for reconciliation errors

**Resolution**:

1. Add required annotations to custom resources
2. Verify operator namespace configuration
3. Check for resource validation errors

## Validation

### Expected Outcomes

1. **Operator Deployment**: Pod shows `Running` status with no restarts
2. **CRD Management**: Custom resources are created and managed automatically
3. **Reconciliation**: Operator logs show successful reconciliation loops
4. **Resource Efficiency**: Memory usage under 500Mi, CPU under 200m

### Validation Commands

```bash
# Verify operator deployment
kubectl get deployment -n observability victoria-metrics-operator -o json | jq '.status.availableReplicas'

# Check operator conditions
kubectl get pods -n observability -l app.kubernetes.io/name=victoria-metrics-operator -o json | jq '.items[0].status.conditions'
```

## Escalation

- **CRD Issues**: Contact platform team for custom resource definition problems
- **RBAC Problems**: Escalate to security team for permission configuration
- **Operator Configuration**: Consult with monitoring team for advanced settings
- **Storage Integration**: Engage storage team for Rook Ceph configuration

## Maintenance

### Updates

1. Review operator release notes before upgrading
2. Test new versions with sample custom resources
3. Update values.yaml for breaking changes

### Backups

1. Operator configuration stored in Git
2. Custom resources backed up via Velero
3. Verify backup status: `velero get backups | grep observability`

## References

- [VictoriaMetrics Operator Documentation](https://docs.victoriametrics.com/operator/)
- [Custom Resource API Reference](https://docs.victoriametrics.com/operator/api/)
- [Helm Chart Values](https://github.com/VictoriaMetrics/helm-charts/blob/master/charts/victoria-metrics-operator/values.yaml)

## Change History

- **2025-12-04**: Initial documentation created during documentation maintenance workflow
