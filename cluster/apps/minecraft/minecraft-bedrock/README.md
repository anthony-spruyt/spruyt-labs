# Minecraft Bedrock - Game Server

## Overview

Minecraft Bedrock Edition server provides the core gaming experience for Bedrock Edition clients. In the spruyt-labs homelab, this server hosts the primary Minecraft world and gameplay environment for Bedrock Edition players.

## Directory Layout

```yaml
minecraft-bedrock/
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
- Persistent storage for Minecraft world data
- Network connectivity for Minecraft protocols
- Proper resource allocation for game server
- Backup configuration for world data

## Operation

### Procedures

1. **Server management**:

   ```bash
   # Check server status
   kubectl logs -n minecraft <minecraft-bedrock-pod> | grep "Server started"

   # Monitor player activity
   kubectl logs -n minecraft <minecraft-bedrock-pod> | grep "player joined"
   ```

2. **World management**:

   ```bash
   # Check world backup status
   kubectl get pvc -n minecraft

   # Monitor world size
   kubectl exec -it <test-pod> -n minecraft -- du -sh /data/worlds
   ```

3. **Configuration updates**:

   ```bash
   # Update server properties
   kubectl apply -f values.yaml

   # Restart server for configuration changes
   kubectl rollout restart deployment minecraft-bedrock -n minecraft
   ```

### Decision Trees

```yaml
# Minecraft Bedrock operational decision tree
start: "minecraft_bedrock_health_check"
nodes:
  minecraft_bedrock_health_check:
    question: "Is Minecraft Bedrock healthy?"
    command: "kubectl get pods -n minecraft --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "minecraft_bedrock_healthy"
  investigate_issue:
    action: "kubectl describe pods -n minecraft | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      resource_constraint: "Resource limitation"
      storage_issue: "Storage or persistence problem"
      network_connectivity: "Network connectivity issue"
      configuration_error: "Configuration mismatch"
  resource_constraint:
    action: "Check resource usage: kubectl top pods -n minecraft"
    next: "apply_fix"
  storage_issue:
    action: "Check persistent volume: kubectl get pvc -n minecraft"
    next: "apply_fix"
  network_connectivity:
    action: "Test network connectivity: kubectl exec -it <test-pod> -n minecraft -- nc -zv minecraft-bedrock 19132"
    next: "apply_fix"
  configuration_error:
    action: "Review values.yaml and server properties"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n minecraft --no-headers | grep 'Running'"
    yes: "minecraft_bedrock_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  minecraft_bedrock_healthy:
    action: "Minecraft Bedrock verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# Minecraft Bedrock cross-service dependencies
service_dependencies:
  minecraft_bedrock:
    depends_on:
      - kube-system/cilium
      - observability/victoria-metrics-k8s-stack
      - rook-ceph/rook-ceph
      - minecraft/bedrock-connect
    depended_by:
      - Bedrock Edition clients
      - Cross-platform players via Bedrock Connect
      - World backup systems
    critical_path: false
    health_check_command: "kubectl get pods -n minecraft --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Resource constraints**:

   - **Symptom**: Server lag or crashes
   - **Diagnosis**: Check CPU/memory usage
   - **Resolution**: Scale resources or optimize server settings

2. **World corruption**:

   - **Symptom**: World loading failures
   - **Diagnosis**: Check world data integrity
   - **Resolution**: Restore from backup

3. **Connection problems**:

   - **Symptom**: Players unable to join
   - **Diagnosis**: Test network connectivity
   - **Resolution**: Verify network policies and firewall rules

4. **Backup failures**:

   - **Symptom**: World data not backed up
   - **Diagnosis**: Check backup job status
   - **Resolution**: Verify backup configuration

## Maintenance

### Updates

```bash
# Update Minecraft Bedrock using Flux
flux reconcile kustomization minecraft-bedrock --with-source

# Check update status
kubectl get helmreleases -n minecraft
```

### World Management

```bash
# Trigger manual world backup
kubectl exec -it <backup-pod> -n minecraft -- backup-world

# Restore world from backup
kubectl exec -it <restore-pod> -n minecraft -- restore-world <backup-name>
```

### MCP Integration

- **Library ID**: `minecraft-bedrock-server`
- **Version**: `v1.20.0`
- **Usage**: Minecraft Bedrock Edition game server
- **Citation**: Use `resolve-library-id` for Minecraft server configuration

## References

- [Minecraft Bedrock Documentation](https://minecraft.net/)
- [Minecraft Server Administration](https://minecraft.fandom.com/wiki/Server)
- [Kubernetes Stateful Applications](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)

## Agent-Friendly Workflows

### Minecraft Bedrock Health Check Workflow

```yaml
# Minecraft Bedrock health check decision tree
start: "check_minecraft_bedrock_pods"
nodes:
  check_minecraft_bedrock_pods:
    question: "Are Minecraft Bedrock pods running?"
    command: "kubectl get pods -n minecraft --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_server_port"
    no: "restart_minecraft_pods"
  check_server_port:
    question: "Is Minecraft server port listening?"
    command: "kubectl exec -n minecraft deployment/minecraft-bedrock -- netstat -tln | grep -c ':19132'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "PORT_FAIL"}'' | grep -q ''OK'''
    yes: "check_world_data"
    no: "fix_server_config"
  check_world_data:
    question: "Is world data accessible?"
    command: "kubectl exec -n minecraft deployment/minecraft-bedrock -- ls -la /data/worlds | grep -c 'bedrock'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "WORLD_FAIL"}'' | grep -q ''OK'''
    yes: "minecraft_bedrock_healthy"
    no: "restore_world_backup"
  restart_minecraft_pods:
    action: "Restart Minecraft Bedrock pods"
    next: "check_minecraft_bedrock_pods"
  fix_server_config:
    action: "Check Minecraft server configuration and ports"
    next: "check_server_port"
  restore_world_backup:
    action: "Restore world data from backup"
    next: "check_world_data"
  minecraft_bedrock_healthy:
    action: "Minecraft Bedrock game server is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for Minecraft Bedrock documentation.
- Confirm the catalog entry contains the documentation or API details needed for Minecraft Bedrock operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers Minecraft Bedrock documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed Minecraft Bedrock configuration changes.

### When Minecraft Bedrock documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in Minecraft Bedrock change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting Minecraft Bedrock documentation.
