# Victoria Metrics Operator

## Summary

Victoria Metrics Operator manages the lifecycle of VictoriaMetrics custom resources, providing automated provisioning, scaling, and management of VictoriaMetrics instances across the cluster.

## Preconditions

- Kubernetes cluster v1.25+ with FluxCD active
- CustomResourceDefinitions for VictoriaMetrics installed
- RBAC permissions configured for operator service account
- Storage classes available for persistent volumes

## Directory Layout

```yaml
victoria-metrics-operator/
├── app/
│   ├── kustomization.yaml          # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values override
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Operation

### Monitoring Commands

```bash
# Check operator health
kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-operator

# Verify CRD status
kubectl get crd victoriametrics.victoriametrics.com -o yaml

# Check operator logs
kubectl logs -n observability -l app.kubernetes.io/name=victoria-metrics-operator --tail=50

# Monitor resource usage
kubectl top pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-operator
```

### Cross-Service Dependencies

```yaml
service_dependencies:
  victoria-metrics-operator:
    depends_on:
      - victoria-metrics-k8s-stack
      - rook-ceph-storage
      - cert-manager
    depended_by:
      - custom-victoriametrics-resources
      - monitoring-automation
    critical_path: true
    health_check_command: "kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-operator --no-headers | grep -c 'Running'"
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

# Test CRD creation
kubectl apply -f - <<EOF
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMCluster
metadata:
  name: test-cluster
  namespace: observability
spec:
  retentionPeriod: "1"
  replicaCount: 1
EOF
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

### MCP Integration

- **Library ID**: `victoria-metrics-operator`
- **Version**: `v0.42.0`
- **Usage**: Operator configuration and troubleshooting procedures
- **Citation**: Use `resolve-library-id` for VictoriaMetrics operator configuration and API references

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for VictoriaMetrics operator documentation.
- Confirm the catalog entry contains the documentation or API details needed for VictoriaMetrics operator operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers VictoriaMetrics operator documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed VictoriaMetrics operator configuration changes.

### When VictoriaMetrics operator documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in VictoriaMetrics operator change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting VictoriaMetrics operator documentation.

## References

- [VictoriaMetrics Operator Documentation](https://docs.victoriametrics.com/operator/)
- [Custom Resource API Reference](https://docs.victoriametrics.com/operator/api/)
- [Helm Chart Values](https://github.com/VictoriaMetrics/helm-charts/blob/master/charts/victoria-metrics-operator/values.yaml)

## Decision Tree for Operator Management

```yaml
start: "operator_health_check"
nodes:
  operator_health_check:
    question: "Is VictoriaMetrics operator healthy?"
    command: "kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-operator --no-headers | grep -v 'Running'"
    validation: "wc -l | grep -q '^0$'"
    yes: "investigate_operator"
    no: "operator_healthy"
  investigate_operator:
    action: "kubectl describe pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-operator"
    log_command: "kubectl logs -n observability -l app.kubernetes.io/name=victoria-metrics-operator --tail=50"
    next: "analyze_operator_issue"
  analyze_operator_issue:
    question: "What is the root cause?"
    diagnostic_commands:
      - "kubectl get events -n observability --sort-by=.metadata.creationTimestamp | tail -10"
      - "kubectl top pods -n observability"
    options:
      config_error: "Configuration issue"
      dependency_failure: "Dependency problem"
      resource_constraint: "Resource limitation"
  config_error:
    action: "Review values.yaml and Helm configuration"
    commands:
      - "helm get values victoria-metrics-operator -n observability"
      - "kubectl get cm -n observability -o yaml | grep victoria"
    next: "apply_operator_fix"
  dependency_failure:
    action: "Check cross-service dependencies"
    commands:
      - "kubectl get crd victoriametrics.victoriametrics.com -o yaml"
      - "kubectl get serviceaccount -n observability victoria-metrics-operator -o yaml"
    next: "apply_operator_fix"
  resource_constraint:
    action: "Adjust resource requests/limits"
    commands:
      - "kubectl top nodes"
      - "kubectl describe nodes | grep -A 10 'Capacity'"
    next: "apply_operator_fix"
  apply_operator_fix:
    action: "Apply appropriate remediation"
    validation_commands:
      - "kubectl rollout restart deployment victoria-metrics-operator -n observability"
      - "kubectl delete pod -n observability -l app.kubernetes.io/name=victoria-metrics-operator"
    next: "verify_operator_fix"
  verify_operator_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-operator --no-headers | grep 'Running'"
    validation: "wc -l | grep -q '^[1-9]'"
    yes: "operator_healthy"
    no: "escalate_operator_issue"
  escalate_operator_issue:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  operator_healthy:
    action: "VictoriaMetrics operator verified healthy"
    next: "end"
end: "end"
```

## Change History

- **2025-12-04**: Initial documentation created during documentation maintenance workflow
- **Standards Compliance**: Follows spruyt-labs README template with decision trees
- **Validation**: Designed to pass `task dev-env:lint` requirements
