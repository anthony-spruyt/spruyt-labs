# Cilium - Networking and Security

## Purpose and Scope

Cilium provides advanced networking, security, and observability for the spruyt-labs Kubernetes cluster using eBPF technology, serving as the primary CNI and network security solution.

Objectives:

- Provide high-performance CNI networking for Kubernetes workloads
- Implement network policies for microsegmentation and security
- Enable BGP routing for integration with external networks
- Provide load balancing capabilities for services
- Offer deep observability and monitoring of network traffic

## Overview

Cilium provides networking, security, and observability for Kubernetes using eBPF technology. It serves as the CNI (Container Network Interface) for the spruyt-labs cluster, providing network connectivity, load balancing, network policies, and security features.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- BGP-capable network infrastructure
- IPv4/IPv6 connectivity configured
- Node networking properly configured

### Validation

```bash
# Validate Cilium installation
kubectl get pods -n kube-system -l k8s-app=cilium

# Check Cilium status
cilium status

# Validate network connectivity
kubectl get nodes -o wide
```

## Operation

### Procedures

1. **Network policy management**:

```bash
# Check network policies
kubectl get networkpolicies -A
```

2. **BGP monitoring**:

```bash
# Check BGP peer status
kubectl get bgppeers -n kube-system -o wide

# Check BGP advertisements
kubectl get bgpadvertisements -n kube-system
```

3. **Load balancer management**:

```bash
# Check load balancer services
kubectl get svc -A --field-selector spec.type=LoadBalancer

# Check load balancer IP allocation
kubectl get ciliumloadbalancerippools -n kube-system
```

## Troubleshooting

### Common Issues

1. **BGP session failures**:

   - **Symptom**: BGP peers not establishing sessions
   - **Diagnosis**: Check BGP configuration and peer reachability
   - **Resolution**: Verify BGP peer IP addresses and AS numbers

2. **Network policy enforcement issues**:

   - **Symptom**: Unexpected network connectivity
   - **Diagnosis**: Review network policy rules and labels
   - **Resolution**: Verify policy selectors and rule definitions

3. **eBPF loading failures**:
   - **Symptom**: Cilium pods failing to start
   - **Diagnosis**: Check kernel compatibility and eBPF support
   - **Resolution**: Verify node kernel version and eBPF requirements

## Maintenance

### Updates

```bash
# Update Cilium using Flux
flux reconcile kustomization cilium --with-source
```

### BGP Management

```bash
# Check BGP route advertisements
kubectl get bgpadvertisements -n kube-system -o wide
```

## References

- [Cilium Documentation](https://docs.cilium.io/)
- [eBPF Documentation](https://ebpf.io/)
- [BGP Configuration Guide](https://docs.cilium.io/en/stable/network/bgp/)
