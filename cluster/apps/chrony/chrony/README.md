# chrony - NTP Time Synchronization

## Overview

Chrony is a versatile implementation of the Network Time Protocol (NTP) that provides precise time synchronization for the Kubernetes cluster. It ensures all nodes maintain accurate time, which is critical for distributed systems, logging, authentication, and other time-sensitive operations in the spruyt-labs homelab infrastructure.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Proper network connectivity for NTP servers
- Appropriate firewall rules allowing NTP traffic (UDP port 123)
- Cluster nodes with proper time synchronization requirements

## Operation

### Procedures

1. **Time synchronization monitoring**:

   ```bash
   # Check chrony service status
   kubectl get pods -n chrony

   # Verify time synchronization
   kubectl exec -n chrony <pod-name> -- chronyc tracking

   # Check time sources
   kubectl exec -n chrony <pod-name> -- chronyc sources
   ```

2. **Configuration management**:

   ```bash
   # Check current configuration
   kubectl exec -n chrony <pod-name> -- cat /etc/chrony/chrony.conf

   # Verify NTP server connectivity
   kubectl exec -n chrony <pod-name> -- chronyc ntpdata
   ```

3. **Performance monitoring**:

   ```bash
   # Check time offset and synchronization status
   kubectl exec -n chrony <pod-name> -- chronyc tracking

   # Monitor time sources
   kubectl exec -n chrony <pod-name> -- chronyc sources -v
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate time synchronization monitoring
kubectl get pods -n chrony --no-headers | grep 'Running'

# Expected: At least one pod in Running state

# Validate configuration management
kubectl exec -n chrony <pod-name> -- chronyc tracking

# Expected: Time synchronization status displayed

# Validate performance monitoring
kubectl exec -n chrony <pod-name> -- chronyc sources

# Expected: NTP sources listed with status
```

## Troubleshooting

### Common Issues

1. **NTP server connectivity failures**:

   - **Symptom**: Time synchronization not working
   - **Diagnosis**: Check NTP server connectivity and firewall rules
   - **Resolution**: Verify NTP server addresses and network connectivity

2. **Time drift issues**:

   - **Symptom**: Significant time offset from NTP servers
   - **Diagnosis**: Check chrony tracking and sources
   - **Resolution**: Verify NTP server configuration and network latency

3. **Resource constraints**:

   - **Symptom**: Pods in Pending state or frequent restarts
   - **Diagnosis**: Check resource requests vs available cluster resources
   - **Resolution**: Adjust resource limits or scale cluster

4. **Configuration errors**:

   - **Symptom**: Chrony service not starting
   - **Diagnosis**: Check configuration syntax and NTP server addresses
   - **Resolution**: Verify values.yaml configuration

## Maintenance

### Updates

```bash
# Update chrony using Flux
flux reconcile kustomization chrony --with-source
```

### Configuration Management

```bash
# Update chrony configuration
flux reconcile kustomization chrony --with-source

# Verify configuration changes
kubectl exec -n chrony <pod-name> -- cat /etc/chrony/chrony.conf
```

## References

- [Chrony Documentation](https://chrony.tuxfamily.org/)
- [NTP Protocol Specification](https://tools.ietf.org/html/rfc5905)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Kubernetes Time Synchronization](https://kubernetes.io/docs/concepts/cluster-administration/manage-deployment/)
