# Cloudflared - Cloudflare Tunnel

## Overview

Cloudflared provides secure tunneling to Cloudflare's global network, enabling private network access to internal services without exposing them to the public internet. It serves as the secure access solution for the spruyt-labs cluster, providing encrypted tunnels for administrative interfaces and internal services.

## Directory Layout

```yaml
cloudflared/
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
- Cloudflare account and credentials
- Proper network connectivity
- DNS records configured in Cloudflare

### Validation

```bash
# Check cloudflared pods are running
kubectl get pods -n cloudflare-system

# Verify tunnel status
kubectl exec -n cloudflare-system deploy/cloudflared -- cloudflared tunnel info

# Check tunnel connectivity
kubectl logs -n cloudflare-system deploy/cloudflared | grep "Connected"

# Verify service connectivity
curl https://<tunnel-name>.cfargotunnel.com
```

## Operation

### Procedures

1. **Tunnel management**:

```bash
   # Check tunnel status
   kubectl exec -n cloudflare-system deploy/cloudflared -- cloudflared tunnel list

   # Check tunnel routes
   kubectl exec -n cloudflare-system deploy/cloudflared -- cloudflared tunnel route show
```

2. **Connectivity monitoring**:

```bash
# Check tunnel logs
kubectl logs -n cloudflare-system deploy/cloudflared -f

# Check tunnel metrics
kubectl exec -n cloudflare-system deploy/cloudflared -- cloudflared tunnel metrics
```

3. **Configuration updates**:

```bash
# Update cloudflared configuration
kubectl apply -f updated-values.yaml

# Restart cloudflared
kubectl rollout restart deploy/cloudflared -n cloudflare-system

```

### Decision Trees

```yaml
# Cloudflared operational decision tree
start: "cloudflared_health_check"
nodes:
  cloudflared_health_check:
    question: "Is cloudflared healthy?"
    command: "kubectl get pods -n cloudflare-system --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "cloudflared_healthy"
  investigate_issue:
    action: "kubectl describe pods -n cloudflare-system | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      tunnel_authentication: "Tunnel authentication problem"
      network_connectivity: "Network connectivity issue"
      configuration_error: "Configuration mismatch"
      resource_constraint: "Resource limitation"
  tunnel_authentication:
    action: "Check tunnel credentials: kubectl exec -n cloudflare-system deploy/cloudflared -- cloudflared tunnel info"
    next: "apply_fix"
  network_connectivity:
    action: "Investigate network connectivity to Cloudflare"
    next: "apply_fix"
  configuration_error:
    action: "Review values.yaml and tunnel configuration"
    next: "apply_fix"
  resource_constraint:
    action: "Adjust resource requests/limits in values.yaml"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n cloudflare-system --no-headers | grep 'Running'"
    yes: "cloudflared_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  cloudflared_healthy:
    action: "Cloudflared verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# Cloudflared cross-service dependencies
service_dependencies:
  cloudflared:
    depends_on:
      - traefik/traefik
      - cert-manager/cert-manager
    depended_by:
      - All services requiring secure external access
      - All administrative interfaces
      - All internal services exposed via tunnel
    critical_path: true
    health_check_command: "kubectl get pods -n cloudflare-system --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Tunnel authentication failures**:

   - **Symptom**: Tunnel not connecting to Cloudflare
   - **Diagnosis**: Check tunnel credentials and authentication
   - **Resolution**: Verify Cloudflare credentials and tunnel configuration

2. **Network connectivity problems**:

   - **Symptom**: Tunnel connectivity issues
   - **Diagnosis**: Check network connectivity and firewall rules
   - **Resolution**: Verify network configuration and Cloudflare connectivity

3. **Configuration synchronization errors**:
   - **Symptom**: Tunnel routes not updating
   - **Diagnosis**: Check configuration synchronization
   - **Resolution**: Verify tunnel configuration and restart cloudflared

## Maintenance

### Updates

```bash
# Update cloudflared
helm repo update
helm upgrade cloudflared cloudflare/cloudflared -n cloudflare-system -f values.yaml
```

### Tunnel Management

```bash
# Check tunnel status
kubectl exec -n cloudflare-system deploy/cloudflared -- cloudflared tunnel list

# Update tunnel configuration
kubectl apply -f updated-cloudflared-values.yaml
```

### MCP Integration

- **Library ID**: `cloudflare-tunnel-cloudflared`
- **Version**: `2024.10.1`
- **Usage**: Secure tunneling to Cloudflare network
- **Citation**: Use `resolve-library-id` for Cloudflared configuration and troubleshooting

## References

- [Cloudflared Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/)
