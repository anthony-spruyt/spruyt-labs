# Crafty Controller - Game Server Management Panel

## Overview

Crafty Controller 4 provides a web-based UI for managing Minecraft Bedrock servers. Enables kids to create servers and install addons without editing YAML files. Runs game servers as child processes within the container (no Docker-in-Docker required).

Priority: low-priority (gaming workload)

> **Note**: HelmRelease resources are managed by Flux in flux-system namespace but deploy workloads to the target namespace specified in ks.yaml.

## Prerequisites

- Kubernetes cluster with Flux CD
- Rook Ceph storage (rbd-fast-delete StorageClass)
- Traefik ingress controller
- `CRAFTY_CONTROLLER_IP4` defined in cluster-secrets

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n minecraft -l app.kubernetes.io/name=crafty-controller
flux get helmrelease -n flux-system crafty-controller

# Force reconcile (GitOps approach)
flux reconcile kustomization crafty-controller --with-source

# View logs
kubectl logs -n minecraft -l app.kubernetes.io/name=crafty-controller
```

### Web Access

Access the panel at `https://crafty.lan.${EXTERNAL_DOMAIN}`. Create admin account on first login.

### Creating Bedrock Servers

1. In Crafty UI: Create new server -> Select Bedrock
2. Configure port (use 19132-19139 range)
3. Start server

### Installing Addons

1. Select server -> Files
2. Upload .mcpack/.mcaddon to `behavior_packs/` or `resource_packs/`
3. Restart server

## Troubleshooting

### Common Issues

1. **Web UI not accessible**
   - **Symptom**: Cannot reach `crafty.lan.${EXTERNAL_DOMAIN}`
   - **Resolution**: Check ingress and certificate status:
     ```bash
     kubectl get ingressroute -n minecraft
     kubectl get certificate -n minecraft
     ```

2. **Game connection failed**
   - **Symptom**: Players cannot connect to server
   - **Resolution**: Verify LoadBalancer and server status:
     ```bash
     kubectl get svc -n minecraft crafty-controller-bedrock
     ```

3. **Storage permission errors**
   - **Symptom**: Crafty cannot write to data directories
   - **Resolution**: Check PVC binding and init container logs:
     ```bash
     kubectl get pvc -n minecraft crafty-controller-data
     kubectl logs -n minecraft -l app.kubernetes.io/name=crafty-controller -c permissions
     ```

## References

- [Crafty Controller Documentation](https://docs.craftycontrol.com/)
- [Crafty Controller GitLab](https://gitlab.com/crafty-controller/crafty-4)
