# vaultwarden - Password Manager

## Overview

Vaultwarden is an unofficial Bitwarden-compatible server implementation that provides secure password management for the spruyt-labs homelab infrastructure. It offers a self-hosted solution for storing and managing sensitive credentials with end-to-end encryption.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Persistent storage configured for data persistence
- TLS certificates available for secure connections
- SMTP server configured for email notifications
- Rook Ceph storage provisioned (dependency)

## Operation

### Procedures

1. **Password manager management**:

   - Access vaultwarden web interface
   - Monitor user authentication and data storage
   - Manage backup and restore procedures

2. **Persistent volume monitoring**:

   ```bash
   # Check persistent volume claims
   kubectl get pvc -n vaultwarden

   # Verify volume binding
   kubectl get pv | grep vaultwarden
   ```

3. **Certificate renewal monitoring**:

   ```bash
   # Check certificate expiration
   kubectl get certificates -n vaultwarden -o wide

   # Check certificate events
   kubectl get events -n vaultwarden | grep certificate
   ```

## Troubleshooting

### Common Issues

1. **Persistent volume binding failures**:

   - **Symptom**: Pods stuck in Pending state
   - **Diagnosis**: Check PVC status and storage class availability
   - **Resolution**: Verify Rook Ceph storage provisioning and PVC configuration

2. **TLS certificate issues**:

   - **Symptom**: Web interface connection failures
   - **Diagnosis**: Check cert-manager certificate status and TLS configuration
   - **Resolution**: Verify certificate DNS names and issuer configuration

3. **Resource constraints**:

   - **Symptom**: Pods in Pending state or frequent restarts
   - **Diagnosis**: Check resource requests vs available cluster resources
   - **Resolution**: Adjust resource limits or scale cluster

4. **Network connectivity issues**:

   - **Symptom**: Web interface inaccessible
   - **Diagnosis**: Check network policies and ingress configuration
   - **Resolution**: Verify network connectivity and firewall rules

## Maintenance

### Updates

```bash
# Update vaultwarden using Flux
flux reconcile kustomization vaultwarden --with-source
```

### Backups

```bash
# Verify persistent volume backups
kubectl get pvc -n vaultwarden

# Check backup status if using Velero
kubectl get backups -n vaultwarden
```

## References

- [Vaultwarden Documentation](https://github.com/dani-garcia/vaultwarden)
- [Bitwarden API Documentation](https://bitwarden.com/help/api/)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Rook Ceph Documentation](https://rook.io/docs/rook/latest/)
