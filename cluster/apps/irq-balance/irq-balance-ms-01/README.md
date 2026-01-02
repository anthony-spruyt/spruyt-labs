# irq-balance-ms-01 - IRQ and RSS Tuning for MS-01 Nodes

## Overview

IRQ Balance is a Linux daemon that distributes hardware interrupts across multiple CPUs to improve system performance. This deployment includes both IRQ balancing and RSS (Receive Side Scaling) tuning for MS-01 nodes.

**Components:**
- **irqbalance daemon**: Distributes hardware interrupts across available P-cores
- **RSS tuning (init container)**: Configures network card flow distribution to prevent thermal hotspots

## Prerequisites

- Kubernetes cluster with proper node access
- Management server (ms-01) with appropriate CPU configuration
- Proper kernel support for IRQ balancing
- Network connectivity for node management

## Operation

### Procedures

1. **Verify RSS tuning (init container)**:

```bash
# Check that RSS tuning init container completed successfully
kubectl logs -n irq-balance -l app.kubernetes.io/name=irq-balance-ms-01 -c tune-rss

# Verify RSS indirection table on node
kubectl run ethtool-check --image=nicolaka/netshoot:latest --namespace=dev-debug \
  --restart=Never --rm --overrides='{
    "spec": {
      "hostNetwork": true,
      "nodeName": "ms-01-2",
      "containers": [{
        "name": "ethtool",
        "image": "nicolaka/netshoot:latest",
        "command": ["ethtool", "-x", "enp89s0"],
        "securityContext": {"privileged": true}
      }]
    }
  }'

# Monitor interrupt distribution (should be balanced)
talosctl -n ms-01-2 read /proc/interrupts | grep "eth1-TxRx"
```

2. **IRQ balancing monitoring**:

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

1. **RSS tuning not applied**:

   - **Symptom**: Network interrupts still concentrated on single CPU
   - **Diagnosis**: Check init container logs: `kubectl logs -n irq-balance <pod> -c tune-rss`
   - **Resolution**: Verify NIC supports RSS, ensure init container has privileged mode
   - **Note**: RSS only affects new network flows; existing connections stay on original queue

2. **Node access problems**:

   - **Symptom**: Pod unable to access management server
   - **Diagnosis**: Check node status and access permissions
   - **Resolution**: Verify node labels and taints

3. **IRQ balancing not working**:

   - **Symptom**: Uneven IRQ distribution
   - **Diagnosis**: Check IRQ balance configuration and kernel support
   - **Resolution**: Verify IRQ balance parameters and kernel modules

4. **Resource constraints**:

   - **Symptom**: Pods in Pending state or frequent restarts
   - **Diagnosis**: Check resource requests vs available cluster resources
   - **Resolution**: Adjust resource limits or scale cluster

5. **Configuration errors**:

   - **Symptom**: IRQ balance service not starting
   - **Diagnosis**: Check configuration syntax and parameters
   - **Resolution**: Verify values.yaml configuration

## Maintenance

### Updates

```bash
# Update irq-balance-ms-01 using Flux
flux reconcile kustomization irq-balance-ms-01 --with-source
```

### Configuration Management

```bash
# Update irq-balance-ms-01 configuration
flux reconcile kustomization irq-balance-ms-01 --with-source

# Verify configuration changes
kubectl exec -n irq-balance <pod-name> -- cat /etc/default/irqbalance
```

## References

- [IRQ Balance Documentation](https://github.com/irqbalance/irqbalance)
- [RSS (Receive Side Scaling)](https://www.kernel.org/doc/html/latest/networking/scaling.html)
- [ethtool RSS Configuration](https://www.kernel.org/doc/Documentation/networking/scaling.txt)
- [Issue #236: CPU thermal throttling](https://github.com/anthony-spruyt/spruyt-labs/issues/236)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Kubernetes Node Management](https://kubernetes.io/docs/concepts/architecture/nodes/)
