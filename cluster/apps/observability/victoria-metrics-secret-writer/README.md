# Victoria Metrics Secret Writer

## Summary

Victoria Metrics Secret Writer automates the creation and management of Kubernetes secrets containing VictoriaMetrics configuration, credentials, and sensitive data. This component ensures secure and automated secret provisioning for the observability stack.

## Preconditions

- Kubernetes cluster with FluxCD active
- RBAC permissions for secret creation and management
- Service account with appropriate permissions
- Target namespaces exist for secret deployment

## Directory Layout

```yaml
victoria-metrics-secret-writer/
├── app/
│   ├── etcd-secret-writer.yaml     # Secret writer configuration
│   ├── kustomization.yaml          # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── role.yaml                   # RBAC role definition
│   ├── role-binding.yaml            # RBAC role binding
│   ├── service-account.yaml        # Service account
│   └── values.yaml                 # Configuration values
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Operation

### Monitoring Commands

```bash
# Check secret writer deployment
kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-secret-writer

# Verify service account
kubectl get sa -n observability victoria-metrics-secret-writer

# Check RBAC permissions
kubectl get role,rolebinding -n observability | grep victoria-metrics

# Monitor secret creation
kubectl get secrets -A --field-selector=type=victoriametrics.com/managed
```

### Cross-Service Dependencies

```yaml
service_dependencies:
  victoria-metrics-secret-writer:
    depends_on:
      - cert-manager
      - rook-ceph-storage
    depended_by:
      - victoria-metrics-k8s-stack
      - victoria-logs-single
      - observability-components
    critical_path: true
    health_check_command: "kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-secret-writer --no-headers | grep -c 'Running'"
```

## Troubleshooting

### Common Issues

#### Symptom: Secrets not being created

**Diagnosis**:

- Check secret writer logs for permission errors
- Verify service account RBAC configuration
- Review target namespace existence and accessibility

**Resolution**:

1. Validate service account permissions with `kubectl auth can-i`
2. Check target namespace labels and annotations
3. Review secret writer configuration in values.yaml

#### Symptom: Secret content malformed or incomplete

**Diagnosis**:

- Examine secret writer logs for template errors
- Verify input data sources and templates
- Check for missing or incorrect values in configuration

**Resolution**:

1. Validate template syntax in configuration
2. Check source data availability and format
3. Review secret structure requirements

## Validation

### Expected Outcomes

1. **Deployment Success**: Secret writer pod shows `Running` status
2. **RBAC Functional**: Service account has required permissions
3. **Secret Creation**: Target secrets created with correct structure
4. **Content Validation**: Secrets contain expected VictoriaMetrics configuration

### Validation Commands

```bash
# Verify deployment status
kubectl get deployment -n observability victoria-metrics-secret-writer -o json | jq '.status.availableReplicas'

# Check service account permissions
kubectl auth can-i create secrets --as=system:serviceaccount:observability:victoria-metrics-secret-writer

# Validate secret creation
kubectl get secrets -n <target-namespace> --field-selector=type=victoriametrics.com/managed

# Check secret content structure
kubectl get secret -n <target-namespace> <secret-name> -o json | jq '.data | keys'
```

## Escalation

- **RBAC Issues**: Contact security team for permission troubleshooting
- **Secret Format Problems**: Engage observability team for configuration
- **Template Errors**: Consult with Helm maintainers for syntax
- **Namespace Access**: Escalate to cluster administrators for cross-namespace permissions

## Maintenance

### Updates

1. Review secret structure changes in new versions
2. Test template updates in staging environment
3. Update values.yaml for new secret requirements

### Backups

1. Secret content managed by Git and Flux
2. Configuration backed up via Velero
3. Verify backup status: `velero get backups | grep observability`

### MCP Integration

```yaml
context7_usage:
  library_id: "victoria-metrics-secret-writer"
  version: "v0.5.0"
  source: "VictoriaMetrics secret management documentation"
  retrieved_at: "2025-12-04"
  used_for: "Secret writer configuration and troubleshooting"
```

## References

- [VictoriaMetrics Documentation](https://docs.victoriametrics.com/)
- [Kubernetes Secrets Best Practices](https://kubernetes.io/docs/concepts/configuration/secret/)
- [RBAC for Service Accounts](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Helm Secret Management Patterns](https://helm.sh/docs/chart_best_practices/values/)

## Decision Tree for Secret Management

```yaml
start: "secret_writer_health_check"
nodes:
  secret_writer_health_check:
    question: "Is VictoriaMetrics secret writer healthy?"
    command: "kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-secret-writer --no-headers | grep -v 'Running'"
    yes: "investigate_secret_writer"
    no: "secret_writer_healthy"
  investigate_secret_writer:
    action: "kubectl describe pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-secret-writer"
    log_command: "kubectl logs -n observability -l app.kubernetes.io/name=victoria-metrics-secret-writer --tail=50"
    next: "analyze_secret_writer_issue"
  analyze_secret_writer_issue:
    question: "What type of secret writer issue?"
    diagnostic_commands:
      - "kubectl get sa -n observability victoria-metrics-secret-writer -o yaml"
      - "kubectl get role,rolebinding -n observability | grep victoria-metrics"
      - "kubectl get secrets -A --field-selector=type=victoriametrics.com/managed"
    options:
      rbac_permission: "RBAC permission issue"
      template_error: "Secret template problem"
      namespace_access: "Target namespace inaccessible"
      config_missing: "Configuration values incomplete"
  rbac_permission:
    action: "Verify and correct service account permissions"
    commands:
      - "kubectl auth can-i create secrets --as=system:serviceaccount:observability:victoria-metrics-secret-writer -n <target-namespace>"
      - "kubectl get role -n observability victoria-metrics-secret-writer -o yaml"
    next: "apply_secret_writer_fix"
  template_error:
    action: "Review and correct secret templates"
    commands:
      - "kubectl get cm -n observability -o yaml | grep secret-writer"
      - "helm get values victoria-metrics-secret-writer -n observability"
    next: "apply_secret_writer_fix"
  namespace_access:
    action: "Verify target namespace existence and accessibility"
    commands:
      - "kubectl get ns <target-namespace>"
      - "kubectl auth can-i create secrets -n <target-namespace> --as=system:serviceaccount:observability:victoria-metrics-secret-writer"
    next: "apply_secret_writer_fix"
  config_missing:
    action: "Complete secret writer configuration"
    commands:
      - "kubectl get cm -n observability victoria-metrics-secret-writer-config -o yaml"
      - "kubectl describe pods -n observability -l app.kubernetes.io/name=victoria-metrics-secret-writer"
    next: "apply_secret_writer_fix"
  apply_secret_writer_fix:
    action: "Apply appropriate secret writer remediation"
    validation_commands:
      - "kubectl rollout restart deployment victoria-metrics-secret-writer -n observability"
      - "kubectl delete pod -n observability -l app.kubernetes.io/name=victoria-metrics-secret-writer"
    next: "verify_secret_writer_fix"
  verify_secret_writer_fix:
    question: "Is secret writer issue resolved?"
    command: "kubectl get pods -n observability --selector=app.kubernetes.io/name=victoria-metrics-secret-writer --no-headers | grep 'Running'"
    yes: "secret_writer_healthy"
    no: "escalate_secret_writer_issue"
  escalate_secret_writer_issue:
    action: "Escalate with secret writer diagnostics and RBAC status to security team"
    next: "end"
  secret_writer_healthy:
    action: "VictoriaMetrics secret writer verified healthy"
    next: "end"
end: "end"
```

## Change History

- **2025-12-04**: Initial documentation created during documentation maintenance workflow
- **Standards Compliance**: Follows spruyt-labs README template with decision trees
- **Validation**: Designed to pass `task dev-env:lint` requirements
