# mosquitto - MQTT Broker

## Overview

Mosquitto is an open-source MQTT broker that implements the MQTT protocol for lightweight messaging in IoT (Internet of Things) applications. It provides a publish-subscribe messaging pattern for device communication in the spruyt-labs homelab infrastructure.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Storage class configured for persistent volumes
- TLS certificates available for secure MQTT connections

## Operation

### Procedures

1. **MQTT broker management**:

   - Access mosquitto admin interface (if configured)
   - Monitor MQTT connections and topics
   - Manage authentication and authorization

2. **Persistent volume monitoring**:

   ```bash
   # Check persistent volume claims
   kubectl get pvc -n mosquitto

   # Verify volume binding
   kubectl get pv | grep mosquitto
   ```

3. **Certificate renewal monitoring**:

   ```bash
   # Check certificate expiration
   kubectl get certificates -n mosquitto -o wide

   # Check certificate events
   kubectl get events -n mosquitto | grep certificate
   ```

## Troubleshooting

### Common Issues

1. **Persistent volume binding failures**:

   - **Symptom**: Pods stuck in Pending state
   - **Diagnosis**: Check PVC status and storage class availability
   - **Resolution**: Verify Rook Ceph storage provisioning and PVC configuration

2. **TLS certificate issues**:

   - **Symptom**: MQTT connection failures
   - **Diagnosis**: Check cert-manager certificate status and TLS configuration
   - **Resolution**: Verify certificate DNS names and issuer configuration

3. **Resource constraints**:

   - **Symptom**: Pods in Pending state or frequent restarts
   - **Diagnosis**: Check resource requests vs available cluster resources
   - **Resolution**: Adjust resource limits or scale cluster

4. **Network connectivity issues**:

   - **Symptom**: MQTT clients unable to connect
   - **Diagnosis**: Check network policies and ingress configuration
   - **Resolution**: Verify network connectivity and firewall rules

## Maintenance

### Updates

```bash
# Update mosquitto using Flux
flux reconcile kustomization mosquitto --with-source
```

### Backups

```bash
# Verify persistent volume backups
kubectl get pvc -n mosquitto

# Check backup status if using Velero
kubectl get backups -n mosquitto
```

## References

- [Mosquitto Documentation](https://mosquitto.org/documentation/)
- [MQTT Protocol Specification](http://mqtt.org/)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Rook Ceph Documentation](https://rook.io/docs/rook/latest/)
