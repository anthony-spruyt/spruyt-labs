# Technitium - DNS Server

## Overview

Technitium is a powerful, open-source DNS server that provides authoritative DNS services. In the spruyt-labs homelab infrastructure, Technitium serves as the primary DNS server for internal domain resolution, providing reliable and configurable DNS services for the homelab environment.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Persistent storage for DNS zone data
- Network connectivity for DNS traffic (UDP/TCP port 53)
- Proper RBAC permissions for DNS operations
- TLS certificates for secure DNS operations

## Operation

### Procedures

1. **DNS zone management**:

   DNS zones are managed through the Technitium web UI or its HTTP API. Access the web interface to view and manage zones.

   ```bash
   # Monitor DNS queries
   kubectl logs -n technitium <technitium-pod> | grep "query"
   ```

2. **Performance monitoring**:

   ```bash
   # Check DNS performance
   kubectl top pods -n technitium

   # Monitor response times
   kubectl logs -n technitium <technitium-pod> | grep "response"
   ```

3. **Configuration updates**:

   ```bash
   # Update Technitium configuration
   # Edit values.yaml, commit, then: flux reconcile kustomization technitium --with-source

   # Restart pods for configuration changes
   kubectl rollout restart deployment technitium -n technitium
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate DNS zone management
# Use the Technitium web UI or HTTP API to verify zones

# Validate performance monitoring
kubectl top pods -n technitium

# Expected: Resource usage displayed

# Validate configuration updates
kubectl get pods -n technitium --no-headers | grep 'Running'

# Expected: Pods running after restart
```

## Troubleshooting

### Common Issues

1. **DNS resolution failures**:

   - **Symptom**: DNS queries failing or timing out
   - **Diagnosis**: Check DNS logs and zone configuration
   - **Resolution**: Verify zone files and DNS records

2. **Zone transfer problems**:

   - **Symptom**: Zone transfer failures
   - **Diagnosis**: Check zone transfer logs
   - **Resolution**: Verify zone transfer configuration

3. **Performance bottlenecks**:

   - **Symptom**: High DNS query latency
   - **Diagnosis**: Monitor DNS performance metrics
   - **Resolution**: Scale resources or optimize DNS configuration

4. **TLS certificate issues**:

   - **Symptom**: DNS-over-TLS failures
   - **Diagnosis**: Check certificate status
   - **Resolution**: Verify cert-manager certificate configuration

## Maintenance

### Updates

```bash
# Update Technitium using Flux
flux reconcile kustomization technitium --with-source

# Check update status
flux get hr -n technitium technitium
```

### Zone Management

DNS zones are managed through the Technitium web UI or its HTTP API. There is no CLI tool for Technitium zone management.

## References

- [Technitium Documentation](https://technitium.com/dns/)
- [DNS Protocol Reference](https://www.rfc-editor.org/rfc/rfc1035)
- [Kubernetes DNS Guide](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [DNS Security Best Practices](https://www.ietf.org/rfc/rfc2845.txt)
