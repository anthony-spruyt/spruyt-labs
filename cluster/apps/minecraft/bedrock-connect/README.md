# Minecraft Bedrock Connect - Server List Tool

## Overview

Minecraft Bedrock Connect is a DNS redirect and server list tool that allows Minecraft Bedrock Edition players on consoles (Xbox, PlayStation, Switch) to connect to third-party servers. It works by redirecting DNS queries for featured servers to the Bedrock Connect server, which presents a custom server list UI. In the spruyt-labs homelab, this enables console players to join self-hosted Minecraft servers that aren't on the official featured server list.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Network connectivity for Minecraft protocols
- Proper UDP port forwarding for game traffic
- DNS configuration for Minecraft domains
- Sufficient network bandwidth for game traffic

## Operation

### Procedures

1. **Connection management**:

   ```bash
   # Check active connections
   kubectl logs -n minecraft <bedrock-connect-pod> | grep "connection"

   # Monitor player traffic
   kubectl logs -n minecraft <bedrock-connect-pod> | grep "player"
   ```

2. **Performance monitoring**:

   ```bash
   # Check network throughput
   kubectl top pods -n minecraft

   # Monitor error rates
   kubectl logs -n minecraft <bedrock-connect-pod> | grep "error"
   ```

3. **Configuration updates**:

   ```bash
   # Update configuration
   # Edit values.yaml, commit, then: flux reconcile kustomization bedrock-connect --with-source

   # Restart pods for configuration changes
   kubectl rollout restart deployment bedrock-connect -n minecraft
   ```

## Troubleshooting

### Common Issues

1. **Connection failures**:

   - **Symptom**: Players unable to connect
   - **Diagnosis**: Check network connectivity and port forwarding
   - **Resolution**: Verify Cilium network policies and firewall rules

2. **Protocol compatibility issues**:

   - **Symptom**: Connection drops or protocol errors
   - **Diagnosis**: Check protocol version compatibility
   - **Resolution**: Update Bedrock Connect configuration

3. **Performance bottlenecks**:

   - **Symptom**: High latency or connection timeouts
   - **Diagnosis**: Monitor network throughput and resource usage
   - **Resolution**: Scale resources or optimize network

4. **Authentication problems**:

   - **Symptom**: Authentication failures
   - **Diagnosis**: Check authentication configuration
   - **Resolution**: Verify authentication backend connectivity

## Maintenance

### Updates

```bash
# Update Bedrock Connect using Flux
flux reconcile kustomization bedrock-connect --with-source

# Check update status
kubectl get helmreleases -n minecraft
```

### Configuration Management

```bash
# Update Minecraft server configuration
# Edit values.yaml, commit, then: flux reconcile kustomization bedrock-connect --with-source

# Restart service for configuration changes
kubectl rollout restart deployment bedrock-connect -n minecraft
```

## References

- [Bedrock Connect Documentation](https://github.com/Pugmatt/BedrockConnect)
- [Kubernetes Networking Guide](https://kubernetes.io/docs/concepts/services-networking/)
- [UDP Load Balancing](https://kubernetes.io/docs/tasks/access-application-cluster/create-external-load-balancer/#preserving-the-client-source-ip)
