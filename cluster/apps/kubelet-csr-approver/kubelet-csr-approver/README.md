# Kubelet CSR Approver - Certificate Signing Request Management

## Overview

Kubelet CSR Approver automates the approval of Kubernetes Certificate Signing Requests (CSRs) for kubelet serving certificates. It provides automated certificate rotation and management for kubelet nodes, ensuring secure and up-to-date TLS certificates for node communication.

## Directory Layout

```yaml
kubelet-csr-approver/
├── app/
│   ├── kustomization.yaml            # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

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

### Decision Trees

```yaml
# Kubelet CSR approver decision tree
start: "csr_approver_health_check"
nodes:
  csr_approver_health_check:
    question: "Is CSR approver healthy?"
    command: "kubectl get pods -n kubelet-csr-approver --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "csr_approver_healthy"
  investigate_issue:
    action: "kubectl describe pods -n kubelet-csr-approver | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      rbac_permission: "RBAC permission problem"
      certificate_authority: "Certificate authority issue"
      node_connectivity: "Node connectivity problem"
      resource_constraint: "Resource limitation"
  rbac_permission:
    action: "Check RBAC configuration: kubectl get clusterroles | grep csr"
    next: "apply_fix"
  certificate_authority:
    action: "Verify certificate authority configuration"
    next: "apply_fix"
  node_connectivity:
    action: "Investigate node-to-api-server connectivity"
    next: "apply_fix"
  resource_constraint:
    action: "Adjust resource requests/limits in values.yaml"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n kubelet-csr-approver --no-headers | grep 'Running'"
    yes: "csr_approver_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  csr_approver_healthy:
    action: "CSR approver verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# Kubelet CSR approver cross-service dependencies
service_dependencies:
  kubelet-csr-approver:
    depends_on:
      - cert-manager/cert-manager
    depended_by:
      - All Kubernetes nodes
      - All workloads requiring node certificates
      - All components using kubelet TLS
    critical_path: true
    health_check_command: "kubectl get pods -n kubelet-csr-approver --no-headers | grep 'Running'"
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
# Update kubelet CSR approver
helm repo update
helm upgrade kubelet-csr-approver kubelet-csr-approver/kubelet-csr-approver -n kubelet-csr-approver -f values.yaml
```

### CSR Management

```bash
# Check pending CSRs
kubectl get csr

# Approve pending CSRs
kubectl certificate approve <csr-name>
```

### MCP Integration

- **Library ID**: `kubelet-csr-approver`
- **Version**: `v1.2.0`
- **Usage**: Automated kubelet certificate signing request approval
- **Citation**: Use `resolve-library-id` for CSR approver configuration and troubleshooting

## References

- [Kubernetes CSR Documentation](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/)
- [Kubelet CSR Approver GitHub](https://github.com/postfinance/kubelet-csr-approver)
- [Kubernetes Authentication](https://kubernetes.io/docs/reference/access-authn-authz/authentication/)
