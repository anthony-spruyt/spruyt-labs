# Cloudflared - Cloudflare Tunnel

## Overview

Cloudflared provides secure tunneling to Cloudflare's global network, enabling private network access to internal services without exposing them to the public internet. It serves as the secure access solution for the spruyt-labs cluster, providing encrypted tunnels for administrative interfaces and internal services.

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

## References

- [Cloudflared Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/)
