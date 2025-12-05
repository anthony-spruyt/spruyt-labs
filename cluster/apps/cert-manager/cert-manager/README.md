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

## Directory Layout

```yaml
cert-manager/
├── app/
│   ├── cluster-issuers.yaml          # Cluster-wide issuer configurations
│   ├── kustomization.yaml            # Kustomize configuration
│   ├── kustomizeconfig.yaml          # Kustomize config
│   ├── release.yaml                  # Helm release configuration
│   └── values.yaml                   # Helm values
├── ks.yaml                           # Kustomization configuration
└── README.md                         # This file
```

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Ingress controller configured
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

### Decision Trees

```yaml
# cert-manager operational decision tree
start: "cert_manager_health_check"
nodes:
  cert_manager_health_check:
    question: "Is cert-manager healthy?"
    command: "kubectl get pods -n cert-manager --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "cert_manager_healthy"
  investigate_issue:
    action: "kubectl describe pods -n cert-manager | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      issuer_config_error: "Issuer configuration problem"
      dns_challenge_failure: "DNS challenge failure"
      rate_limit_hit: "Let's Encrypt rate limit"
      network_issue: "Network connectivity"
  issuer_config_error:
    action: "Check cluster issuer configuration: kubectl get clusterissuers -o yaml"
    next: "apply_fix"
  dns_challenge_failure:
    action: "Verify DNS records and challenge configuration"
    next: "apply_fix"
  rate_limit_hit:
    action: "Check Let's Encrypt rate limits and wait"
    next: "apply_fix"
  network_issue:
    action: "Investigate network connectivity to issuer endpoints"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation using Flux reconciliation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n cert-manager --no-headers | grep 'Running'"
    yes: "cert_manager_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  cert_manager_healthy:
    action: "cert-manager verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# cert-manager cross-service dependencies
service_dependencies:
  cert-manager:
    depends_on:
      - traefik/traefik
      - external-dns/external-dns-technitium
    depended_by:
      - authentik-system/authentik
      - traefik/traefik
      - All services requiring TLS certificates
    critical_path: true
    health_check_command: "kubectl get pods -n cert-manager --no-headers | grep 'Running'"
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

### Backups

```bash
# Backup cert-manager configuration
kubectl get clusterissuers -o yaml > cert-manager-clusterissuers-backup.yaml
kubectl get certificates -A -o yaml > cert-manager-certificates-backup.yaml

# Restore from backup
kubectl apply -f cert-manager-clusterissuers-backup.yaml
kubectl apply -f cert-manager-certificates-backup.yaml
```

### MCP Integration

- **Library ID**: `cert-manager`
- **Version**: `v1.13.3`
- **Usage**: TLS certificate automation and management
- **Citation**: Use `resolve-library-id` for cert-manager API and configuration references

## References

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Flux CD Documentation](https://fluxcd.io/flux/)

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of cert-manager tasks.

### Certificate Health Check Workflow

```bash
If kubectl get certificates -A --no-headers | grep -v 'True' > /dev/null
Then:
  Run kubectl describe certificate <cert-name> -n <namespace>
  Expected output: Certificate details and status
  If status shows 'False':
    Run flux reconcile kustomization cert-manager --with-source
    Expected output: Reconciliation completed
    Recovery: Certificate re-issued
  Else:
    Proceed to next check
Else:
  Proceed to next check
```

## Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for cert-manager documentation.
- Confirm the catalog entry contains the documentation or API details needed for cert-manager operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers cert-manager documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed cert-manager configuration changes.

### When cert-manager documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in cert-manager change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting cert-manager documentation.
