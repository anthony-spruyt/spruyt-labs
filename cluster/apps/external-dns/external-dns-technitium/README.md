# external-dns-technitium - DNS Management

## Overview

ExternalDNS is a Kubernetes controller that automatically manages DNS records based on Kubernetes resources. The technitium variant integrates with Technitium DNS server to provide dynamic DNS management for the spruyt-labs homelab infrastructure, ensuring that DNS records are automatically created, updated, and deleted as services are deployed or removed.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Technitium DNS server configured and accessible
- Proper DNS zone configuration in Technitium
- API credentials for Technitium DNS server
- Network connectivity to Technitium DNS server

## Operation

### Procedures

1. **DNS record management**:

```bash
# Check external-dns service status
kubectl get pods -n external-dns

# Verify DNS record synchronization
kubectl logs -n external-dns <pod-name> | grep "record"

# Check Technitium API connectivity
kubectl logs -n external-dns <pod-name> | grep "API"
```

2. **Configuration management**:

```bash
# Check current configuration
kubectl get configmap -n external-dns

# Verify Technitium DNS server connectivity
kubectl logs -n external-dns <pod-name> | grep "Technitium"
```

3. **Performance monitoring**:

   ```bash
   # Check DNS record synchronization status
   kubectl logs -n external-dns <pod-name> | grep "synchronization"

   # Monitor API call performance
   kubectl logs -n external-dns <pod-name> | grep "API call"
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate DNS record management
kubectl logs -n external-dns <pod-name> | grep "record"

# Expected: DNS record synchronization logs

# Validate configuration management
kubectl get configmap -n external-dns

# Expected: Configuration maps listed

# Validate performance monitoring
kubectl logs -n external-dns <pod-name> | grep "synchronization"

# Expected: Synchronization status logs
```

## Troubleshooting

### Common Issues

1. **Technitium DNS server connectivity failures**:

   - **Symptom**: DNS records not being created
   - **Diagnosis**: Check Technitium DNS server connectivity and API status
   - **Resolution**: Verify Technitium DNS server configuration and network connectivity

2. **API authentication errors**:

   - **Symptom**: Authentication failures in logs
   - **Diagnosis**: Check API credentials and Technitium DNS server configuration
   - **Resolution**: Verify API credentials and Technitium DNS server access

3. **DNS record synchronization delays**:

   - **Symptom**: Slow DNS record updates
   - **Diagnosis**: Check Technitium DNS server performance and API response times
   - **Resolution**: Verify Technitium DNS server resources and network latency

4. **Configuration errors**:

   - **Symptom**: ExternalDNS service not starting
   - **Diagnosis**: Check configuration syntax and Technitium DNS server addresses
   - **Resolution**: Verify values.yaml configuration

## Maintenance

### Updates

```bash
# Update external-dns-technitium using Flux
flux reconcile kustomization external-dns-technitium --with-source
```

### Configuration Management

```bash
# Update external-dns-technitium configuration
flux reconcile kustomization external-dns-technitium --with-source

# Verify configuration changes
kubectl logs -n external-dns <pod-name> | grep "configuration"
```

## References

- [ExternalDNS Documentation](https://github.com/kubernetes-sigs/external-dns)
- [Technitium DNS Documentation](https://technitium.com/dns/)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Kubernetes Ingress Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)
