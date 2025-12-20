# External Secrets - Secrets Management

## Overview

External Secrets Operator manages Kubernetes secrets by synchronizing them from external secret management systems. It provides a secure way to retrieve secrets from external sources like AWS Secrets Manager, HashiCorp Vault, and other secret stores, and inject them into Kubernetes as native Secret resources.

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

## References

- [External Secrets Documentation](https://external-secrets.io/)
- [External Secrets Operator GitHub](https://github.com/external-secrets/external-secrets)
- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
