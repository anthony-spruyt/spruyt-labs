# Traefik - Ingress Controller

## Overview

Traefik is a modern HTTP reverse proxy and load balancer that serves as the ingress controller for the spruyt-labs Kubernetes cluster. It provides routing, load balancing, TLS termination, and observability for all incoming traffic to the cluster.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- cert-manager deployed for TLS certificate management
- DNS properly configured for domains
- Load balancer IP addresses available

## Operation

### Procedures

1. **Ingress route management**:

```bash
# Add new ingress route
kubectl apply -f ingress/<workload>/ingress-route.yaml

# Check ingress route status
kubectl get ingressroutes -A -o wide
```

2. **TLS certificate monitoring**:

   ```bash
   # Check certificate status
   kubectl get certificates -A

   # Check certificate events
   kubectl get events -A | grep certificate
   ```

3. **Traefik dashboard access**:

```bash
# Access Traefik dashboard
kubectl port-forward svc/traefik -n traefik 9000:9000

# Check Traefik metrics
kubectl port-forward svc/traefik -n traefik 8082:8082
```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate ingress route management
kubectl get ingressroutes -A -o wide

# Expected: Ingress routes listed with status

# Validate TLS certificate monitoring
kubectl get certificates -A

# Expected: Certificates listed

# Validate Traefik dashboard access
kubectl port-forward svc/traefik -n traefik 9000:9000

# Expected: Port forward successful
```

## Troubleshooting

### Common Issues

1. **Ingress route not working**:

   - **Symptom**: 404 errors on ingress routes
   - **Diagnosis**: Check ingress route configuration and service endpoints
   - **Resolution**: Verify route hostnames, service names, and ports

2. **TLS certificate errors**:

   - **Symptom**: Browser certificate warnings
   - **Diagnosis**: Check cert-manager certificate status
   - **Resolution**: Verify certificate DNS names and issuer configuration

3. **Load balancer connectivity issues**:
   - **Symptom**: External access failures
   - **Diagnosis**: Check load balancer service and Cilium BGP configuration
   - **Resolution**: Verify BGP advertisements and load balancer IP allocation

## Maintenance

### Updates

```bash
# Update Traefik Helm chart
helm repo update
helm upgrade traefik traefik/traefik -n traefik -f values.yaml
```

### Ingress Route Management

```bash
# Add new ingress route
kubectl apply -f ingress/<workload>/ingress-route.yaml

# Update existing ingress route
kubectl apply -f ingress/<workload>/updated-ingress-route.yaml
```

## References

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [IngressRoute CRD Reference](https://doc.traefik.io/traefik/providers/kubernetes-crd/)
- [Traefik Helm Chart](https://github.com/traefik/traefik-helm-chart)
