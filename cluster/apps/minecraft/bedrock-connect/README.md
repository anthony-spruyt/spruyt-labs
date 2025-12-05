# Minecraft Bedrock Connect - Cross-Platform Bridge

## Overview

Minecraft Bedrock Connect is a proxy service that enables cross-platform play between Minecraft Bedrock Edition and Java Edition. In the spruyt-labs homelab, this service allows players on different platforms to connect and play together seamlessly.

## Directory Layout

```yaml
bedrock-connect/
├── app/
│   ├── kustomization.yaml            # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Network connectivity for Minecraft protocols
- Proper UDP port forwarding for game traffic
- DNS configuration for Minecraft domains
- Sufficient network bandwidth for game traffic

## Operation

### Procedures

1. **Connection management**:

   ```bash
   # Check active connections
   kubectl logs -n minecraft <bedrock-connect-pod> | grep "connection"

   # Monitor player traffic
   kubectl logs -n minecraft <bedrock-connect-pod> | grep "player"
   ```

2. **Performance monitoring**:

   ```bash
   # Check network throughput
   kubectl top pods -n minecraft

   # Monitor error rates
   kubectl logs -n minecraft <bedrock-connect-pod> | grep "error"
   ```

3. **Configuration updates**:

   ```bash
   # Update configuration
   kubectl apply -f values.yaml

   # Restart pods for configuration changes
   kubectl rollout restart deployment bedrock-connect -n minecraft
   ```

### Decision Trees

```yaml
# Bedrock Connect operational decision tree
start: "bedrock_connect_health_check"
nodes:
  bedrock_connect_health_check:
    question: "Is Bedrock Connect healthy?"
    command: "kubectl get pods -n minecraft --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "bedrock_connect_healthy"
  investigate_issue:
    action: "kubectl describe pods -n minecraft | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      network_connectivity: "Network connectivity issue"
      protocol_mismatch: "Protocol compatibility problem"
      resource_constraint: "Resource limitation"
      configuration_error: "Configuration mismatch"
  network_connectivity:
    action: "Test network connectivity: kubectl exec -it <test-pod> -n minecraft -- nc -zv bedrock-connect 19132"
    next: "apply_fix"
  protocol_mismatch:
    action: "Check protocol logs: kubectl logs -n minecraft <bedrock-connect-pod> | grep 'protocol'"
    next: "apply_fix"
  resource_constraint:
    action: "Check resource usage: kubectl top pods -n minecraft"
    next: "apply_fix"
  configuration_error:
    action: "Review values.yaml and Helm configuration"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n minecraft --no-headers | grep 'Running'"
    yes: "bedrock_connect_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  bedrock_connect_healthy:
    action: "Bedrock Connect verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# Bedrock Connect cross-service dependencies
service_dependencies:
  bedrock_connect:
    depends_on:
      - kube-system/cilium
      - observability/victoria-metrics-k8s-stack
      - traefik/traefik
    depended_by:
      - Minecraft Bedrock Edition clients
      - Minecraft Java Edition clients
      - Minecraft server instances
    critical_path: false
    health_check_command: "kubectl get pods -n minecraft --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Connection failures**:

   - **Symptom**: Players unable to connect
   - **Diagnosis**: Check network connectivity and port forwarding
   - **Resolution**: Verify Cilium network policies and firewall rules

2. **Protocol compatibility issues**:

   - **Symptom**: Connection drops or protocol errors
   - **Diagnosis**: Check protocol version compatibility
   - **Resolution**: Update Bedrock Connect configuration

3. **Performance bottlenecks**:

   - **Symptom**: High latency or connection timeouts
   - **Diagnosis**: Monitor network throughput and resource usage
   - **Resolution**: Scale resources or optimize network

4. **Authentication problems**:

   - **Symptom**: Authentication failures
   - **Diagnosis**: Check authentication configuration
   - **Resolution**: Verify authentication backend connectivity

## Maintenance

### Updates

```bash
# Update Bedrock Connect using Flux
flux reconcile kustomization bedrock-connect --with-source

# Check update status
kubectl get helmreleases -n minecraft
```

### Configuration Management

```bash
# Update Minecraft server configuration
kubectl apply -f values.yaml

# Restart service for configuration changes
kubectl rollout restart deployment bedrock-connect -n minecraft
```

### MCP Integration

- **Library ID**: `minecraft-bedrock-connect`
- **Version**: `v1.16.0`
- **Usage**: Cross-platform Minecraft connectivity
- **Citation**: Use `resolve-library-id` for Bedrock Connect configuration

## References

- [Bedrock Connect Documentation](https://github.com/Pugmatt/BedrockConnect)
- [Kubernetes Networking Guide](https://kubernetes.io/docs/concepts/services-networking/)
- [UDP Load Balancing](https://kubernetes.io/docs/tasks/access-application-cluster/create-external-load-balancer/#preserving-the-client-source-ip)

## Agent-Friendly Workflows

### Bedrock Connect Health Check Workflow

```yaml
# Bedrock Connect health check decision tree
start: "check_bedrock_connect_pods"
nodes:
  check_bedrock_connect_pods:
    question: "Are Bedrock Connect pods running?"
    command: "kubectl get pods -n minecraft --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_udp_port"
    no: "restart_bedrock_connect_pods"
  check_udp_port:
    question: "Is UDP port listening?"
    command: "kubectl exec -n minecraft deployment/bedrock-connect -- netstat -uln | grep -c ':19132'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "UDP_FAIL"}'' | grep -q ''OK'''
    yes: "check_connection_handling"
    no: "fix_udp_config"
  check_connection_handling:
    question: "Is connection handling working?"
    command: "kubectl logs -n minecraft -l app.kubernetes.io/name=bedrock-connect --tail=20 | grep -c 'connection\\|player\\|query'"
    validation: 'awk ''{if ($1 >= 0) print "OK"; else print "CONN_FAIL"}'' | grep -q ''OK'''
    yes: "bedrock_connect_healthy"
    no: "fix_connection_config"
  restart_bedrock_connect_pods:
    action: "Restart Bedrock Connect pods"
    next: "check_bedrock_connect_pods"
  fix_udp_config:
    action: "Check UDP port configuration and network policies"
    next: "check_udp_port"
  fix_connection_config:
    action: "Check connection handling and protocol configuration"
    next: "check_connection_handling"
  bedrock_connect_healthy:
    action: "Bedrock Connect cross-platform bridge is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for Bedrock Connect documentation.
- Confirm the catalog entry contains the documentation or API details needed for Bedrock Connect operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers Bedrock Connect documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed Bedrock Connect configuration changes.

### When Bedrock Connect documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in Bedrock Connect change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting Bedrock Connect documentation.
