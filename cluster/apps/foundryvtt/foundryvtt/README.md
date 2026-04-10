# Foundry VTT

## Overview

Foundry Virtual Tabletop (Foundry VTT) is a modern, self-hosted virtual tabletop application designed for playing tabletop role-playing games over the internet.

It provides a robust platform for game masters and players to collaborate in immersive gaming experiences with features like dynamic lighting, token management, audio/video integration, and extensive module support.

This deployment runs Foundry VTT in a Kubernetes cluster using Flux for GitOps management.

## Prerequisites

- **Namespace**: `foundryvtt` (created via `namespace.yaml`)
- **Secrets**: `foundryvtt-secrets` containing Foundry VTT license key and other sensitive configuration
- **Storage**: Ceph RBD storage class `rbd-fast-delete` with 10Gi PVC for persistent data
- **Dependencies**:
  - Flux for GitOps deployment management
  - cert-manager for TLS certificate management
  - external-dns for DNS record management (if external access required)
  - Traefik ingress controller for routing
- **Tools**: kubectl, talosctl, flux CLI for management

## Operation

### Procedures

#### Deployment

The application is deployed via Flux Kustomization. Changes to the configuration are automatically reconciled.

```bash
# Check deployment status
flux get kustomizations -n flux-system | grep foundryvtt

# Reconcile manually if needed
flux reconcile kustomization foundryvtt -n flux-system
```

#### Access

Foundry VTT is accessed via HTTPS through Traefik ingress routes. Configure ingress routes for external or LAN access following the procedures in `../procedures.md`.

For external access, create ingress routes in `cluster/apps/traefik/traefik/ingress/foundryvtt/` with:

- Host: `foundryvtt.${EXTERNAL_DOMAIN}`
- TLS secret: `foundryvtt-${EXTERNAL_DOMAIN/./-}-tls`

For LAN access, use `foundryvtt.lan.${EXTERNAL_DOMAIN}`.

### Monitoring Commands

```bash
# Check pod status
kubectl get pods -n foundryvtt

# View application logs
kubectl logs -n foundryvtt -l app.kubernetes.io/name=foundryvtt --tail=100

# Monitor resource usage
kubectl top pods -n foundryvtt

# Check ingress routes
kubectl get ingressroute -n foundryvtt

# Verify certificates
kubectl get certificates -n foundryvtt

# Check Flux reconciliation
flux get kustomizations foundryvtt -n flux-system
```

## Troubleshooting

### Common Issues

#### Foundry VTT Won't Start

**Symptoms**: Pod in CrashLoopBackoff or InitContainer failures

**Diagnosis**:

```bash
kubectl logs -n foundryvtt -l app.kubernetes.io/name=foundryvtt --previous
kubectl describe deployment foundryvtt -n foundryvtt
```

**Common Causes**:

- Invalid license key in secrets
- Insufficient permissions on data directory
- Storage mount failures

**Resolution**:

- Verify `foundryvtt-secrets` contains valid FOUNDRY_LICENSE_KEY
- Check PVC status: `kubectl get pvc foundryvtt-data -n foundryvtt`
- Review init container logs for permission issues

#### HTTPS Certificate Issues

**Symptoms**: Browser shows certificate warnings or connection refused

**Diagnosis**:

```bash
kubectl get certificates -n foundryvtt
kubectl describe certificate foundryvtt-<domain>-tls -n foundryvtt
```

**Resolution**:

- Ensure cert-manager is running: `kubectl get pods -n cert-manager-system`
- Check DNS propagation for external access
- Verify ingress route configuration

#### High Resource Usage

**Symptoms**: Pod restarts due to OOM or high CPU

**Diagnosis**:

```bash
kubectl top pods -n foundryvtt
kubectl describe deployment foundryvtt -n foundryvtt | grep -A 10 "Containers:"
```

**Resolution**:

- Increase memory limits in `values.yaml`
- Adjust UV_THREADPOOL_SIZE and NODE_OPTIONS for performance tuning
- Monitor active gaming sessions and module usage

#### External Access Unavailable

**Symptoms**: Cannot reach Foundry VTT from external networks

**Diagnosis**:

```bash
kubectl get ingressroute -n foundryvtt
nslookup foundryvtt.${EXTERNAL_DOMAIN}
```

**Resolution**:

- Verify external-dns annotations on ingress routes
- Check Traefik deployment: `kubectl get pods -n traefik`
- Confirm DNS propagation

## Maintenance

### Backups

Foundry VTT data is automatically backed up using Velero, following the homelab's automation-first approach. Backups are scheduled and managed through the Velero deployment in the cluster.

```bash
# Check backup status
velero backup get

# List backup schedules
velero schedule get

# Restore from backup if needed
velero restore create --from-backup <backup-name>
```

### Updates

Foundry VTT updates are managed through Renovate. Major version updates should be tested:

```bash
# Check current version
kubectl get pods -n foundryvtt -l app.kubernetes.io/name=foundryvtt -o jsonpath='{.items[0].spec.containers[0].image}'

# Update via Renovate PR or manual values.yaml change
# Test after update
kubectl logs -n foundryvtt -l app.kubernetes.io/name=foundryvtt | grep "Foundry Virtual Tabletop"
```

### Log Rotation

Application logs are managed by Kubernetes. For extended retention:

```bash
# Export logs for analysis
kubectl logs -n foundryvtt -l app.kubernetes.io/name=foundryvtt --since=24h > foundryvtt-logs.txt
```

### Performance Tuning

Monitor and adjust based on usage:

- **Memory**: Increase NODE_OPTIONS --max-old-space-size for large worlds
- **CPU**: Adjust UV_THREADPOOL_SIZE based on concurrent users
- **Storage**: Monitor disk usage via PVC: `kubectl get pvc -n foundryvtt`

## References

- [Foundry VTT Official Documentation](https://foundryvtt.com/article/installation/)
- [felddy/foundryvtt-docker GitHub](https://github.com/felddy/foundryvtt-docker)
- [BJW-S Labs Helm Charts](https://github.com/bjw-s-labs/helm-charts)
- [Flux Documentation](https://fluxcd.io/)
- [cert-manager Documentation](https://cert-manager.io/)
