# mosquitto - MQTT Broker

## Overview

Mosquitto is an open-source MQTT broker that implements the MQTT protocol for lightweight messaging in IoT (Internet of Things) applications. It provides a publish-subscribe messaging pattern for device communication in the spruyt-labs homelab infrastructure.

## Directory Layout

```yaml
mosquitto/
├── app/
│   ├── certificate.yaml                # TLS certificate configuration
│   ├── kustomization.yaml              # Kustomize configuration
│   ├── kustomizeconfig.yaml            # Kustomize config
│   ├── persistent-volume-claim.yaml     # Persistent volume claims
│   ├── release.yaml                    # Helm release configuration
│   └── values.yaml                     # Helm values
├── ks.yaml                             # Kustomization configuration
└── README.md                           # This file
```

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Storage class configured for persistent volumes
- Ingress controller configured for MQTT protocol
- TLS certificates available for secure MQTT connections
- Rook Ceph storage provisioned (dependency)

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

### Decision Trees

```yaml
# mosquitto operational decision tree
start: "mosquitto_health_check"
nodes:
  mosquitto_health_check:
    question: "Is mosquitto healthy?"
    command: "kubectl get pods -n mosquitto --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "mosquitto_healthy"
  investigate_issue:
    action: "kubectl describe pods -n mosquitto | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      storage_issue: "Persistent volume problem"
      config_error: "Configuration mismatch"
      resource_constraint: "Resource limitation"
      network_issue: "Network connectivity"
      tls_issue: "TLS certificate problem"
  storage_issue:
    action: "Check PVC and PV: kubectl get pvc -n mosquitto"
    next: "apply_fix"
  config_error:
    action: "Review values.yaml and Helm configuration"
    next: "apply_fix"
  resource_constraint:
    action: "Adjust resource requests/limits in values.yaml"
    next: "apply_fix"
  network_issue:
    action: "Investigate network policies and connectivity"
    next: "apply_fix"
  tls_issue:
    action: "Check certificate status: kubectl get certificates -n mosquitto"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n mosquitto --no-headers | grep 'Running'"
    yes: "mosquitto_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  mosquitto_healthy:
    action: "mosquitto verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# mosquitto cross-service dependencies
service_dependencies:
  mosquitto:
    depends_on:
      - rook-ceph/rook-ceph-cluster
      - traefik/traefik
      - cert-manager/cert-manager
    depended_by:
      - IoT devices and applications
      - Home automation systems
    critical_path: true
    health_check_command: "kubectl get pods -n mosquitto --no-headers | grep 'Running'"
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

### MCP Integration

- **Library ID**: `mosquitto-mqtt-broker`
- **Version**: `2.0.18`
- **Usage**: MQTT messaging and IoT device communication
- **Citation**: Use `resolve-library-id` for mosquitto configuration and API references

## References

- [Mosquitto Documentation](https://mosquitto.org/documentation/)
- [MQTT Protocol Specification](http://mqtt.org/)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Rook Ceph Documentation](https://rook.io/docs/rook/latest/)

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of mosquitto tasks.

### mosquitto Health Check Workflow

```yaml
# mosquitto health check decision tree
start: "check_mosquitto_pods"
nodes:
  check_mosquitto_pods:
    question: "Are mosquitto pods running?"
    command: "kubectl get pods -n mosquitto --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_mqtt_port"
    no: "restart_mosquitto_pods"
  check_mqtt_port:
    question: "Is MQTT port listening?"
    command: "kubectl exec -n mosquitto deployment/mosquitto -- netstat -tln | grep -c ':1883\\|:8883'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "PORT_FAIL"}'' | grep -q ''OK'''
    yes: "check_mqtt_connectivity"
    no: "fix_mqtt_config"
  check_mqtt_connectivity:
    question: "Can MQTT clients connect?"
    command: "kubectl logs -n mosquitto -l app.kubernetes.io/name=mosquitto --tail=20 | grep -c 'New client connected\\|Client.*connected'"
    validation: 'awk ''{if ($1 >= 0) print "OK"; else print "CONNECT_FAIL"}'' | grep -q ''OK'''
    yes: "mosquitto_healthy"
    no: "fix_client_connectivity"
  restart_mosquitto_pods:
    action: "Restart mosquitto pods"
    next: "check_mosquitto_pods"
  fix_mqtt_config:
    action: "Check mosquitto configuration and port settings"
    next: "check_mqtt_port"
  fix_client_connectivity:
    action: "Check network policies and client authentication"
    next: "check_mqtt_connectivity"
  mosquitto_healthy:
    action: "Mosquitto MQTT broker is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for mosquitto documentation.
- Confirm the catalog entry contains the documentation or API details needed for mosquitto operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers mosquitto documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed mosquitto configuration changes.

### When mosquitto documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in mosquitto change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting mosquitto documentation.
