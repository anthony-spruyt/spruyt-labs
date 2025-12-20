# Minecraft Bedrock - Game Servers

## Overview

Minecraft Bedrock Edition servers for the spruyt-labs homelab. Deploys two separate game worlds (Creative and Survival) with shared maintenance automation.

## Prerequisites

- Kubernetes cluster with Flux CD
- Rook Ceph storage (dependsOn: rook-ceph-cluster-storage)
- Persistent storage for world data

## Operation

### Key Commands

```bash
# Check both servers
kubectl get pods -n minecraft

# Check specific server
flux get helmrelease -n flux-system minecraft-bedrock-creative
flux get helmrelease -n flux-system minecraft-bedrock-survival

# Force reconcile
flux reconcile kustomization minecraft-bedrock-creative --with-source
flux reconcile kustomization minecraft-bedrock-survival --with-source

# View server logs
kubectl logs -n minecraft -l app.kubernetes.io/name=minecraft-bedrock-creative
kubectl logs -n minecraft -l app.kubernetes.io/name=minecraft-bedrock-survival
```

## Troubleshooting

### Common Issues

1. **Server not starting**

   - **Symptom**: Pod in CrashLoopBackOff
   - **Resolution**: Check logs and PVC status

2. **World data issues**

   - **Symptom**: World loading failures
   - **Resolution**: Check PVC binding and storage health

3. **Connection problems**
   - **Symptom**: Players unable to join
   - **Resolution**: Verify network policies and service ports

## References

- [Minecraft Bedrock Documentation](https://minecraft.net/)
- [itzg/minecraft-bedrock-server](https://github.com/itzg/docker-minecraft-bedrock-server)
