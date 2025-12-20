# Victoria Metrics Secret Writer

## Summary

Victoria Metrics Secret Writer automates the creation and management of Kubernetes secrets containing VictoriaMetrics configuration, credentials, and sensitive data. This component ensures secure and automated secret provisioning for the observability stack.

## Preconditions

- Kubernetes cluster with FluxCD active
- RBAC permissions for secret creation and management
- Service account with appropriate permissions
- Target namespaces exist for secret deployment

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

## References

- [VictoriaMetrics Documentation](https://docs.victoriametrics.com/)
- [Kubernetes Secrets Best Practices](https://kubernetes.io/docs/concepts/configuration/secret/)
- [RBAC for Service Accounts](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Helm Secret Management Patterns](https://helm.sh/docs/chart_best_practices/values/)

## Change History

- **2025-12-04**: Initial documentation created during documentation maintenance workflow
