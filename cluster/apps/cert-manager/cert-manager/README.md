# cert-manager - Certificate Management

## Purpose and Scope

cert-manager provides automated TLS certificate management for the spruyt-labs homelab infrastructure, handling certificate issuance, renewal, and integration with various certificate authorities.

Objectives:

- Automate certificate issuance and renewal processes
- Integrate with multiple certificate issuers (Let's Encrypt, Vault, etc.)
- Provide TLS certificates for ingress resources and services
- Ensure secure communication across the homelab infrastructure

## Overview

cert-manager is a native Kubernetes certificate management controller that automates the management and issuance of TLS certificates. It integrates with various issuers including Let's Encrypt, HashiCorp Vault, and private CAs to provide certificates for ingress resources and other services.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- DNS records properly configured for domains
- Cluster issuer credentials available

### Validation

```bash
# Validate cert-manager installation
kubectl get pods -n cert-manager

# Check cluster issuers
kubectl get clusterissuers

# Validate certificate status
kubectl get certificates -A
```

## Operation

### Procedures

1. **Certificate issuance**:

   - Create Certificate resources in appropriate namespaces using Flux
   - Verify automatic issuance and renewal through Flux reconciliation

2. **Issuer management**:

   ```bash
   # Check issuer status using Flux
   flux get kustomizations -n cert-manager

   # Describe issuer for details
   kubectl describe clusterissuer <issuer-name>
   ```

3. **Certificate renewal monitoring**:

   ```bash
   # Check certificate expiration
   kubectl get certificates -A -o wide

   # Check certificate events
   kubectl get events -A | grep certificate
   ```

## Troubleshooting

### Common Issues

1. **Certificate issuance failures**:

   - **Symptom**: Certificates stuck in "Pending" state
   - **Diagnosis**: Check issuer status and challenge resolution
   - **Resolution**: Verify DNS records and issuer configuration, then use `flux reconcile kustomization cert-manager --with-source`

2. **DNS challenge timeouts**:

   - **Symptom**: Certificate issuance times out
   - **Diagnosis**: Check DNS propagation and challenge configuration
   - **Resolution**: Verify DNS records and challenge solver configuration, then use `flux reconcile kustomization cert-manager --with-source`

3. **Rate limit errors**:
   - **Symptom**: Let's Encrypt rate limit errors
   - **Diagnosis**: Check certificate request frequency
   - **Resolution**: Reduce request frequency or use staging environment, then use `flux reconcile kustomization cert-manager --with-source`

## Maintenance

### Updates

```bash
# Update cert-manager using Flux
flux reconcile kustomization cert-manager --with-source
```

### Issuer Management

```bash
# Add new cluster issuer using Flux
flux reconcile kustomization cert-manager --with-source

# Update existing issuer using Flux
flux reconcile kustomization cert-manager --with-source
```

## References

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Flux CD Documentation](https://fluxcd.io/flux/)
