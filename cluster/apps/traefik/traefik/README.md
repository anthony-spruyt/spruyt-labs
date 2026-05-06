# Traefik - Ingress Controller

## Overview

Traefik is a modern HTTP reverse proxy and load balancer that serves as the ingress controller for the cluster. Provides routing, load balancing, TLS termination, and observability for all incoming traffic.

## Prerequisites

- cert-manager deployed for TLS certificate management

## Troubleshooting

1. **Ingress route not working**

   - **Symptom**: 404 errors on ingress routes
   - **Resolution**: Verify route hostnames, service names, and ports in IngressRoute resources

1. **TLS certificate errors**

   - **Symptom**: Browser certificate warnings
   - **Resolution**: Verify certificate DNS names and issuer configuration via cert-manager

1. **Load balancer connectivity issues**

   - **Symptom**: External access failures
   - **Resolution**: Verify Cilium BGP advertisements and load balancer IP allocation

## References

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [IngressRoute CRD Reference](https://doc.traefik.io/traefik/providers/kubernetes-crd/)
- [Traefik Helm Chart](https://github.com/traefik/traefik-helm-chart)
