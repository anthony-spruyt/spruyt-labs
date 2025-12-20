# Technitium Secondary - DNS Server Replica

## Overview

Technitium Secondary is a replica DNS server that provides redundant DNS services and load balancing for the spruyt-labs homelab infrastructure. This secondary instance works in conjunction with the primary Technitium DNS server to ensure high availability and fault tolerance for DNS resolution.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Primary Technitium DNS server deployed
- Persistent storage for DNS zone data
- Network connectivity for DNS traffic (UDP/TCP port 53)
- Proper RBAC permissions for DNS operations
- Zone transfer configuration between primary and secondary

## Operation

### Procedures

1. **DNS zone synchronization**:

   ```bash
   # Check zone transfer status
   kubectl exec -it <technitium-secondary-pod> -n technitium -- technitium check-sync

   # Monitor zone transfer logs
   kubectl logs -n technitium <technitium-secondary-pod> | grep "transfer"
   ```

2. **Performance monitoring**:

   ```bash
   # Check DNS performance
   kubectl top pods -n technitium | grep secondary

   # Monitor response times
   kubectl logs -n technitium <technitium-secondary-pod> | grep "response"
   ```

3. **Configuration updates**:

   ```bash
   # Update Technitium Secondary configuration
   # Edit values.yaml, commit, then: flux reconcile kustomization technitium-secondary --with-source

   # Restart pods for configuration changes
   kubectl rollout restart deployment technitium-secondary -n technitium
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate DNS zone synchronization
kubectl exec -it <technitium-secondary-pod> -n technitium -- technitium check-sync

# Expected: Synchronization status displayed

# Validate performance monitoring
kubectl top pods -n technitium | grep secondary

# Expected: Resource usage for secondary pod

# Validate configuration updates
kubectl get pods -n technitium --no-headers | grep secondary | grep 'Running'

# Expected: Secondary pod running after restart
```

## Troubleshooting

### Common Issues

1. **Zone synchronization failures**:

   - **Symptom**: Secondary not receiving zone updates
   - **Diagnosis**: Check zone transfer logs and configuration
   - **Resolution**: Verify zone transfer settings and network connectivity

2. **DNS resolution inconsistencies**:

   - **Symptom**: Different responses from primary and secondary
   - **Diagnosis**: Compare zone data between instances
   - **Resolution**: Force zone transfer and verify consistency

3. **Performance bottlenecks**:

   - **Symptom**: High DNS query latency on secondary
   - **Diagnosis**: Monitor DNS performance metrics
   - **Resolution**: Scale resources or optimize DNS configuration

4. **Network connectivity problems**:

   - **Symptom**: Secondary unreachable or intermittent
   - **Diagnosis**: Test network connectivity and DNS
   - **Resolution**: Verify network policies and service discovery

## Maintenance

### Updates

```bash
# Update Technitium Secondary using Flux
flux reconcile kustomization technitium-secondary --with-source

# Check update status
kubectl get helmreleases -n technitium | grep secondary
```

### Zone Synchronization

```bash
# Force zone transfer
kubectl exec -it <technitium-secondary-pod> -n technitium -- technitium force-sync

# Check synchronization status
kubectl exec -it <technitium-secondary-pod> -n technitium -- technitium sync-status
```

## References

- [Technitium Documentation](https://technitium.com/dns/)
- [DNS Zone Transfer Guide](https://www.rfc-editor.org/rfc/rfc5936)
- [Kubernetes High Availability](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/)
- [DNS Redundancy Best Practices](https://www.ietf.org/rfc/rfc2182.txt)
