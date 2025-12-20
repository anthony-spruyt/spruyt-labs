# irq-balance-e2 - IRQ Balancing

## Overview

IRQ Balance is a Linux daemon that distributes hardware interrupts across multiple CPUs to improve system performance. The e2 variant is specifically configured for the edge node in the spruyt-labs homelab infrastructure, ensuring optimal interrupt handling for network-intensive workloads.

## Prerequisites

- Kubernetes cluster with proper node access
- Edge node (e2) with appropriate CPU configuration
- Proper kernel support for IRQ balancing
- Network connectivity for node management

## Operation

### Procedures

1. **IRQ balancing monitoring**:

```bash
# Check irq-balance service status
kubectl get pods -n irq-balance

# Verify IRQ balancing
kubectl exec -n irq-balance <pod-name> -- systemctl status irqbalance

# Check IRQ distribution
kubectl exec -n irq-balance <pod-name> -- cat /proc/interrupts
```

2. **Configuration management**:

```bash
# Check current configuration
kubectl exec -n irq-balance <pod-name> -- cat /etc/default/irqbalance

# Verify IRQ balance configuration
kubectl exec -n irq-balance <pod-name> -- irqbalance --debug
```

3. **Performance monitoring**:

```bash
# Check IRQ balancing status
kubectl exec -n irq-balance <pod-name> -- systemctl status irqbalance

# Monitor IRQ distribution
kubectl exec -n irq-balance <pod-name> -- watch -n 1 cat /proc/interrupts
```

## Troubleshooting

### Common Issues

1. **Node access problems**:

   - **Symptom**: Pod unable to access edge node
   - **Diagnosis**: Check node status and access permissions
   - **Resolution**: Verify node labels and taints

2. **IRQ balancing not working**:

   - **Symptom**: Uneven IRQ distribution
   - **Diagnosis**: Check IRQ balance configuration and kernel support
   - **Resolution**: Verify IRQ balance parameters and kernel modules

3. **Resource constraints**:

   - **Symptom**: Pods in Pending state or frequent restarts
   - **Diagnosis**: Check resource requests vs available cluster resources
   - **Resolution**: Adjust resource limits or scale cluster

4. **Configuration errors**:

   - **Symptom**: IRQ balance service not starting
   - **Diagnosis**: Check configuration syntax and parameters
   - **Resolution**: Verify values.yaml configuration

## Maintenance

### Updates

```bash
# Update irq-balance-e2 using Flux
flux reconcile kustomization irq-balance-e2 --with-source
```

### Configuration Management

```bash
# Update irq-balance-e2 configuration
flux reconcile kustomization irq-balance-e2 --with-source

# Verify configuration changes
kubectl exec -n irq-balance <pod-name> -- cat /etc/default/irqbalance
```

## References

- [IRQ Balance Documentation](https://github.com/irqbalance/irqbalance)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Kubernetes Node Management](https://kubernetes.io/docs/concepts/architecture/nodes/)
