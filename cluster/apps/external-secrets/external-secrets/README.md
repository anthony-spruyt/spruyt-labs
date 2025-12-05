# External Secrets - Secrets Management

## Overview

External Secrets Operator manages Kubernetes secrets by synchronizing them from external secret management systems. It provides a secure way to retrieve secrets from external sources like AWS Secrets Manager, HashiCorp Vault, and other secret stores, and inject them into Kubernetes as native Secret resources.

## Directory Layout

```yaml
external-secrets/
├── app/
│   ├── kustomization.yaml            # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values
├── resources/
│   ├── cluster-rbac.yaml            # Cluster-wide RBAC
│   ├── cluster-secret-store.yaml    # Cluster secret store configuration
│   └── kustomization.yaml          # Resources kustomization
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Prerequisites

- Kubernetes cluster with Flux CD installed
- External secret store configured (AWS, Vault, etc.)
- Proper IAM permissions or authentication configured
- RBAC permissions for secret access

## Operation

### Procedures

1. **External secret management**:

```bash
# Create external secret
kubectl apply -f externalsecret.yaml

# Check external secret status
kubectl get externalsecrets -A -o wide
```

2. **Secret store monitoring**:

```bash
# Check secret store status
kubectl get clustersecretstores -A

# Check secret store events
kubectl get events -A | grep secretstore
```

3. **Secret synchronization verification**:

```bash
# Check synchronized secrets
kubectl get secrets -A

# Check secret data
kubectl get secret <name> -n <namespace> -o yaml

```

### Decision Trees

```yaml
# External Secrets operational decision tree
start: "external_secrets_health_check"
nodes:
  external_secrets_health_check:
    question: "Is External Secrets healthy?"
    command: "kubectl get pods -n external-secrets --no-headers | grep -v 'Running'"
    validation: "wc -l | grep -q '^0$'"
    yes: "investigate_issue"
    no: "external_secrets_healthy"
  investigate_issue:
    action: "kubectl describe pods -n external-secrets"
    log_command: "kubectl logs -n external-secrets <operator-pod-name> --tail=50"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    diagnostic_commands:
      - "kubectl get events -n external-secrets --sort-by=.metadata.creationTimestamp | tail -10"
      - "kubectl top pods -n external-secrets"
    options:
      config_error: "Configuration issue"
      dependency_failure: "Dependency problem"
      resource_constraint: "Resource limitation"
  config_error:
    action: "Review values.yaml and Helm configuration"
    commands:
      - "helm get values external-secrets -n external-secrets"
      - "kubectl get clustersecretstores -A -o yaml"
    next: "apply_fix"
  dependency_failure:
    action: "Check cross-service dependencies"
    commands:
      - "kubectl get pods -n cert-manager"
      - "kubectl auth can-i get secrets --as=system:serviceaccount:external-secrets:external-secrets-sa"
    next: "apply_fix"
  resource_constraint:
    action: "Adjust resource requests/limits"
    commands:
      - "kubectl top nodes"
      - "kubectl describe nodes | grep -A 10 'Capacity'"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    validation_commands:
      - "kubectl apply -f <fixed-config>"
      - "kubectl rollout restart deployment/<deployment> -n external-secrets"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n external-secrets --no-headers | grep 'Running'"
    validation: "wc -l | grep -q '^[1-9]'"
    yes: "external_secrets_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  external_secrets_healthy:
    action: "External Secrets verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# External Secrets cross-service dependencies
service_dependencies:
  external-secrets:
    depends_on:
      - cert-manager/cert-manager
    depended_by:
      - All workloads requiring external secrets
      - All applications using synchronized secrets
      - All services needing secret rotation
    critical_path: true
    health_check_command: "kubectl get pods -n external-secrets --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Secret store connection failures**:

   - **Symptom**: External secrets not synchronizing
   - **Diagnosis**: Check secret store configuration and connectivity
   - **Resolution**: Verify external secret store credentials and network access

2. **Permission errors**:

   - **Symptom**: Access denied errors in logs
   - **Diagnosis**: Check IAM permissions and RBAC
   - **Resolution**: Verify service account permissions and external store access policies

3. **Secret synchronization delays**:
   - **Symptom**: Secrets not updating in timely manner
   - **Diagnosis**: Check refresh intervals and secret store connectivity
   - **Resolution**: Adjust refresh intervals or improve network connectivity

## Maintenance

### Updates

```bash
# Update External Secrets Helm chart
helm repo update
helm upgrade external-secrets external-secrets/external-secrets -n external-secrets -f values.yaml
```

### Secret Store Management

```bash
# Update secret store configuration
kubectl apply -f updated-cluster-secret-store.yaml

# Check secret store status
kubectl get clustersecretstores -A -o wide
```

### MCP Integration

- **Library ID**: `external-secrets-operator`
- **Version**: `v0.9.10`
- **Usage**: External secret synchronization and management
- **Citation**: Use `resolve-library-id` for External Secrets configuration and troubleshooting

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for External Secrets documentation.
- Confirm the catalog entry contains the documentation or API details needed for External Secrets operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers External Secrets documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed External Secrets configuration changes.

### When External Secrets documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in External Secrets change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting External Secrets documentation.

## References

- [External Secrets Documentation](https://external-secrets.io/)
- [External Secrets Operator GitHub](https://github.com/external-secrets/external-secrets)
- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
