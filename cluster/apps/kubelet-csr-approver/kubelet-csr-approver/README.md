# Kubelet CSR Approver - Certificate Signing Request Management

## Overview

Kubelet CSR Approver automates the approval of Kubernetes Certificate Signing Requests (CSRs) for kubelet serving certificates. It provides automated certificate rotation and management for kubelet nodes, ensuring secure and up-to-date TLS certificates for node communication.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Proper RBAC permissions for CSR approval
- Certificate authority configured
- Node connectivity established

## Operation

### Procedures

1. **CSR monitoring**:

```bash
# Check pending CSRs
kubectl get csr

# Approve CSR manually
kubectl certificate approve <csr-name>
```

2. **Certificate rotation monitoring**:

```bash
# Check certificate expiration
kubectl get certificates -A -o wide

# Check node certificate status
kubectl get nodes -o json | jq '.items[].status.conditions[] | select(.type=="Ready")'
```

3. **CSR approver management**:

   ```bash
   # Check approver logs
   kubectl logs -n kubelet-csr-approver deploy/kubelet-csr-approver

   # Check approver events
   kubectl get events -n kubelet-csr-approver
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate CSR monitoring
kubectl get csr

# Expected: CSRs listed with status

# Validate certificate rotation monitoring
kubectl get certificates -A -o wide

# Expected: Certificates listed with expiration dates

# Validate CSR approver management
kubectl logs -n kubelet-csr-approver deploy/kubelet-csr-approver

# Expected: Logs showing approval activity
```

## Troubleshooting

### Common Issues

1. **CSR approval failures**:

   - **Symptom**: CSRs stuck in Pending state
   - **Diagnosis**: Check RBAC permissions and approver logs
   - **Resolution**: Verify RBAC roles and approver configuration

2. **Certificate authority connectivity issues**:

   - **Symptom**: Certificate signing failures
   - **Diagnosis**: Check CA connectivity and configuration
   - **Resolution**: Verify certificate authority endpoints and credentials

3. **Node certificate rotation problems**:
   - **Symptom**: Node communication failures
   - **Diagnosis**: Check node certificate validity and rotation
   - **Resolution**: Verify certificate rotation process and node connectivity

## Maintenance

### Updates

```bash
# Update kubelet CSR approver using Flux
flux reconcile kustomization kubelet-csr-approver --with-source
```

### CSR Management

```bash
# Check pending CSRs
kubectl get csr

# Approve pending CSRs
kubectl certificate approve <csr-name>
```

## References

- [Kubernetes CSR Documentation](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/)
- [Kubelet CSR Approver GitHub](https://github.com/postfinance/kubelet-csr-approver)
- [Kubernetes Authentication](https://kubernetes.io/docs/reference/access-authn-authz/authentication/)
