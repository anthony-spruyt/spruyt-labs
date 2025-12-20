# Whoami - Simple Identification Service

## Overview

Whoami is a simple HTTP service that returns information about the requesting client. In the spruyt-labs homelab infrastructure, Whoami serves as a lightweight testing and debugging tool for network connectivity, load balancing, and ingress routing verification.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Network connectivity for HTTP traffic
- Ingress controller for external access
- Monitoring for service health
- Basic resource allocation

## Operation

### Procedures

1. **Service testing**:

   ```bash
   # Test service response
   kubectl exec -it <test-pod> -n whoami -- curl http://whoami.whoami.svc.cluster.local

   # Check response headers
   kubectl exec -it <test-pod> -n whoami -- curl -I http://whoami.whoami.svc.cluster.local
   ```

2. **Performance monitoring**:

   ```bash
   # Check service performance
   kubectl top pods -n whoami

   # Monitor request logs
   kubectl logs -n whoami <whoami-pod> | grep "request"
   ```

3. **Configuration updates**:

   ```bash
   # Update Whoami configuration
   # Edit values.yaml, commit, then: flux reconcile kustomization whoami --with-source

   # Restart pods for configuration changes
   kubectl rollout restart deployment whoami -n whoami
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate service testing
kubectl exec -it <test-pod> -n whoami -- curl http://whoami.whoami.svc.cluster.local

# Expected: Service response

# Validate performance monitoring
kubectl top pods -n whoami

# Expected: Resource usage

# Validate configuration updates
kubectl get pods -n whoami --no-headers | grep 'Running'

# Expected: Pods running
```

## Troubleshooting

### Common Issues

1. **Connection failures**:

   - **Symptom**: Unable to reach Whoami service
   - **Diagnosis**: Check network connectivity and DNS
   - **Resolution**: Verify Cilium network policies and service discovery

2. **Response errors**:

   - **Symptom**: HTTP error responses
   - **Diagnosis**: Check service logs and configuration
   - **Resolution**: Verify service configuration and resource allocation

3. **Performance bottlenecks**:

   - **Symptom**: High latency or timeouts
   - **Diagnosis**: Monitor resource usage and request patterns
   - **Resolution**: Scale resources or optimize service configuration

4. **Ingress routing problems**:

   - **Symptom**: External access failures
   - **Diagnosis**: Check ingress routes and Traefik configuration
   - **Resolution**: Verify ingress routing and Traefik middleware

## Maintenance

### Updates

```bash
# Update Whoami using Flux
flux reconcile kustomization whoami --with-source

# Check update status
kubectl get helmreleases -n whoami
```

### Service Management

```bash
# Scale service
kubectl scale deployment whoami -n whoami --replicas=3

# Restart service
kubectl rollout restart deployment whoami -n whoami
```

## References

- [Whoami Container](https://hub.docker.com/r/containous/whoami)
- [HTTP Testing Guide](https://developer.mozilla.org/en-US/docs/Web/HTTP)
- [Kubernetes Service Documentation](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Ingress Testing Patterns](https://kubernetes.io/docs/concepts/services-networking/ingress/)
