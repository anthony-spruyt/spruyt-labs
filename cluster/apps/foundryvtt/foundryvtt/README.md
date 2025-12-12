# Foundry VTT

## Overview

Foundry Virtual Tabletop (Foundry VTT) is a modern, self-hosted virtual tabletop application designed for playing tabletop role-playing games over the internet.

It provides a robust platform for game masters and players to collaborate in immersive gaming experiences with features like dynamic lighting, token management, audio/video integration, and extensive module support.

This deployment runs Foundry VTT in a Kubernetes cluster using Flux for GitOps management.

## Directory Layout

- `app/`: Application deployment configuration
  - `kustomization.yaml`: Kustomize configuration for the app resources
  - `kustomizeconfig.yaml`: Kustomize configuration settings
  - `persistent-volume-claim.yaml`: Persistent volume claim for Foundry data storage (10Gi on rbd-fast)
  - `release.yaml`: Flux HelmRelease for deploying the Foundry VTT Helm chart
  - `values.yaml`: Helm values configuration for Foundry VTT deployment
- `ks.yaml`: Flux Kustomization that manages the deployment of this component

## Prerequisites

- **Namespace**: `foundryvtt` (created via `namespace.yaml`)
- **Secrets**: `foundryvtt-secrets` containing Foundry VTT license key and other sensitive configuration
- **Storage**: Ceph RBD storage class `rbd-fast` with 10Gi PVC for persistent data
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

### Decision Trees

```yaml
# Foundry VTT deployment and monitoring decision tree
start: "check_deployment_status"
nodes:
  check_deployment_status:
    question: "Is Foundry VTT deployed and healthy?"
    command: "kubectl get pods -n foundryvtt --no-headers | grep -c 'Running'"
    validation: "grep -q '^1$'"
    yes: "monitor_performance"
    no: "investigate_deployment"
  investigate_deployment:
    action: "Check Flux kustomization and pod status"
    commands:
      - "flux get kustomizations foundryvtt -n flux-system"
      - "kubectl describe pods -n foundryvtt"
      - "kubectl logs -n foundryvtt --tail=50"
    next: "check_root_cause"
  check_root_cause:
    question: "What is the deployment issue?"
    options:
      flux_error: "Flux reconciliation failed"
      pod_error: "Pod startup failure"
      storage_error: "Storage/PVC issue"
      config_error: "Configuration error"
  flux_error:
    action: "Reconcile Flux kustomization and check source"
    commands:
      - "flux reconcile kustomization foundryvtt -n flux-system --with-source"
      - "flux get sources -A | grep foundryvtt"
    next: "verify_deployment"
  pod_error:
    action: "Check pod events and logs for startup issues"
    commands:
      - "kubectl get events -n foundryvtt --sort-by=.metadata.creationTimestamp | tail -10"
      - "kubectl logs foundryvtt-0 -n foundryvtt --previous"
    next: "verify_deployment"
  storage_error:
    action: "Verify PVC status and storage class"
    commands:
      - "kubectl get pvc -n foundryvtt"
      - "kubectl describe pvc foundryvtt-data -n foundryvtt"
    next: "verify_deployment"
  config_error:
    action: "Validate Helm values and secrets"
    commands:
      - "kubectl get secret foundryvtt-secrets -n foundryvtt"
      - "helm get values foundryvtt -n foundryvtt"
    next: "verify_deployment"
  verify_deployment:
    question: "Is deployment issue resolved?"
    command: "kubectl get pods -n foundryvtt --no-headers | grep 'Running'"
    yes: "monitor_performance"
    no: "escalate"
  monitor_performance:
    action: "Monitor resource usage and application health"
    commands:
      - "kubectl top pods -n foundryvtt"
      - "curl -k https://foundryvtt.lan.${EXTERNAL_DOMAIN}/"
    next: "performance_healthy"
  performance_healthy:
    question: "Is performance within acceptable limits?"
    command: 'kubectl top pods -n foundryvtt --no-headers | awk ''{print $3}'' | sed ''s/%//'' | awk ''{if ($1 > 80) print "high"; else print "ok"}'''
    validation: "grep -q 'ok'"
    yes: "end"
    no: "optimize_resources"
  optimize_resources:
    action: "Adjust resource limits in values.yaml"
    next: "end"
  escalate:
    action: "Escalate to human operator with comprehensive diagnostics"
    next: "end"
end: "end"
```

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

### Cross-Service Dependencies

Foundry VTT has the following cross-service dependencies:

- **Flux**: Critical dependency for automated deployment and reconciliation

  - Health check: `flux get kustomizations foundryvtt -n flux-system`
  - Impact: Deployment failures if Flux is unavailable

- **cert-manager**: Required for TLS certificate management

  - Health check: `kubectl get certificates -n foundryvtt`
  - Impact: HTTPS access unavailable if certificates fail

- **external-dns**: Manages DNS records for external access

  - Health check: `kubectl get ingressroute foundryvtt -n foundryvtt -o yaml | grep external-dns`
  - Impact: External DNS resolution fails

- **Traefik**: Provides ingress routing and load balancing

  - Health check: `kubectl get ingressroute -n foundryvtt`
  - Impact: No external access to Foundry VTT

- **Ceph Storage**: Provides persistent storage via rbd-fast storage class
  - Health check: `kubectl get pvc foundryvtt-data -n foundryvtt`
  - Impact: Data loss or startup failures if storage unavailable

## Troubleshooting

### Common Issues

#### Foundry VTT Won't Start

**Symptoms**: Pod in CrashLoopBackoff or InitContainer failures

**Diagnosis**:

```bash
kubectl logs foundryvtt-0 -n foundryvtt --previous
kubectl describe pod foundryvtt-0 -n foundryvtt
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
kubectl describe pod foundryvtt-0 -n foundryvtt | grep -A 10 "Containers:"
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
- Check Traefik deployment: `kubectl get pods -n traefik-system`
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
kubectl get pod foundryvtt-0 -n foundryvtt -o jsonpath='{.spec.containers[0].image}'

# Update via Renovate PR or manual values.yaml change
# Test after update
kubectl logs foundryvtt-0 -n foundryvtt | grep "Foundry Virtual Tabletop"
```

### Log Rotation

Application logs are managed by Kubernetes. For extended retention:

```bash
# Export logs for analysis
kubectl logs foundryvtt-0 -n foundryvtt --since=24h > foundryvtt-logs.txt
```

### Performance Tuning

Monitor and adjust based on usage:

- **Memory**: Increase NODE_OPTIONS --max-old-space-size for large worlds
- **CPU**: Adjust UV_THREADPOOL_SIZE based on concurrent users
- **Storage**: Monitor disk usage: `kubectl exec -n foundryvtt foundryvtt-0 -- df -h /data`

## References

- [Foundry VTT Official Documentation](https://foundryvtt.com/article/installation/)
- [felddy/foundryvtt-docker GitHub](https://github.com/felddy/foundryvtt-docker)
- [BJW-S Labs Helm Charts](https://github.com/bjw-s-labs/helm-charts)
- [Flux Documentation](https://fluxcd.io/)
- [cert-manager Documentation](https://cert-manager.io/)
