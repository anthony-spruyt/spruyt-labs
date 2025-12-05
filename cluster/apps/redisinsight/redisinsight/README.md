# RedisInsight - Visualization Tool

## Overview

RedisInsight is a powerful visualization and management tool for Redis databases. In the spruyt-labs homelab infrastructure, RedisInsight provides comprehensive monitoring, analysis, and administration capabilities for all Redis-compatible data stores.

## Directory Layout

```yaml
redisinsight/
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
- Redis or Valky instances available
- Network connectivity between RedisInsight and data stores
- Proper RBAC permissions for monitoring
- Browser access for web interface

## Operation

### Procedures

1. **Database connection management**:

   ```bash
   # Check connected databases
   kubectl logs -n redisinsight <redisinsight-pod> | grep "connected"

   # Monitor query performance
   kubectl logs -n redisinsight <redisinsight-pod> | grep "performance"
   ```

2. **User access management**:

   ```bash
   # Check authentication logs
   kubectl logs -n redisinsight <redisinsight-pod> | grep "authentication"

   # Monitor active sessions
   kubectl logs -n redisinsight <redisinsight-pod> | grep "session"
   ```

3. **Configuration updates**:

   ```bash
   # Update RedisInsight configuration
   kubectl apply -f values.yaml

   # Restart pods for configuration changes
   kubectl rollout restart deployment redisinsight -n redisinsight
   ```

### Decision Trees

```yaml
# RedisInsight operational decision tree
start: "redisinsight_health_check"
nodes:
  redisinsight_health_check:
    question: "Is RedisInsight healthy?"
    command: "kubectl get pods -n redisinsight --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "redisinsight_healthy"
  investigate_issue:
    action: "kubectl describe pods -n redisinsight | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      database_connectivity: "Database connectivity issue"
      authentication_failure: "Authentication problem"
      resource_constraint: "Resource limitation"
      configuration_error: "Configuration mismatch"
  database_connectivity:
    action: "Test database connectivity: kubectl exec -it <test-pod> -n redisinsight -- redis-cli -h <redis-host> ping"
    next: "apply_fix"
  authentication_failure:
    action: "Check authentication logs: kubectl logs -n redisinsight <redisinsight-pod> | grep 'auth'"
    next: "apply_fix"
  resource_constraint:
    action: "Check resource usage: kubectl top pods -n redisinsight"
    next: "apply_fix"
  configuration_error:
    action: "Review values.yaml and configuration"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n redisinsight --no-headers | grep 'Running'"
    yes: "redisinsight_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  redisinsight_healthy:
    action: "RedisInsight verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# RedisInsight cross-service dependencies
service_dependencies:
  redisinsight:
    depends_on:
      - kube-system/cilium
      - observability/victoria-metrics-k8s-stack
      - valkey-system/valkey
    depended_by:
      - Database administrators
      - Application developers
      - Monitoring and observability tools
    critical_path: false
    health_check_command: "kubectl get pods -n redisinsight --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Database connection failures**:

   - **Symptom**: Unable to connect to Redis instances
   - **Diagnosis**: Check network connectivity and credentials
   - **Resolution**: Verify Cilium network policies and authentication

2. **Authentication problems**:

   - **Symptom**: Login failures or permission errors
   - **Diagnosis**: Check authentication configuration
   - **Resolution**: Verify user credentials and RBAC policies

3. **Performance bottlenecks**:

   - **Symptom**: Slow query execution or timeouts
   - **Diagnosis**: Monitor resource usage and query patterns
   - **Resolution**: Scale resources or optimize queries

4. **Web interface issues**:

   - **Symptom**: UI not loading or displaying errors
   - **Diagnosis**: Check browser console and service logs
   - **Resolution**: Verify service configuration and browser compatibility

## Maintenance

### Updates

```bash
# Update RedisInsight using Flux
flux reconcile kustomization redisinsight --with-source

# Check update status
kubectl get helmreleases -n redisinsight
```

### Database Management

```bash
# Add new database connection
kubectl apply -f new-database-config.yaml

# Remove database connection
kubectl delete -f old-database-config.yaml
```

### MCP Integration

- **Library ID**: `redisinsight-visualization`
- **Version**: `v2.48.0`
- **Usage**: Redis database visualization and management
- **Citation**: Use `resolve-library-id` for RedisInsight configuration

## References

- [RedisInsight Documentation](https://redis.io/docs/latest/)
- [RedisInsight GitHub](https://github.com/RedisInsight/RedisInsight)
- [Redis Commands Reference](https://redis.io/commands)
- [Kubernetes Monitoring Guide](https://kubernetes.io/docs/tasks/debug/)

## Agent-Friendly Workflows

### RedisInsight Health Check Workflow

```yaml
# RedisInsight health check decision tree
start: "check_redisinsight_pods"
nodes:
  check_redisinsight_pods:
    question: "Are RedisInsight pods running?"
    command: "kubectl get pods -n redisinsight --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_web_interface"
    no: "restart_redisinsight_pods"
  check_web_interface:
    question: "Is RedisInsight web interface accessible?"
    command: "kubectl exec -n redisinsight deployment/redisinsight -- curl -s -I http://localhost:8001 | grep -c 'HTTP/1.1 200'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "WEB_FAIL"}'' | grep -q ''OK'''
    yes: "check_redis_connectivity"
    no: "fix_web_interface"
  check_redis_connectivity:
    question: "Can RedisInsight connect to Redis instances?"
    command: "kubectl logs -n redisinsight -l app.kubernetes.io/name=redisinsight --tail=20 | grep -c 'connected\\|success'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "REDIS_FAIL"}'' | grep -q ''OK'''
    yes: "redisinsight_healthy"
    no: "fix_redis_connection"
  restart_redisinsight_pods:
    action: "Restart RedisInsight pods"
    next: "check_redisinsight_pods"
  fix_web_interface:
    action: "Check RedisInsight web server configuration"
    next: "check_web_interface"
  fix_redis_connection:
    action: "Check Redis connection configuration and credentials"
    next: "check_redis_connectivity"
  redisinsight_healthy:
    action: "RedisInsight visualization tool is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for RedisInsight documentation.
- Confirm the catalog entry contains the documentation or API details needed for RedisInsight operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers RedisInsight documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed RedisInsight configuration changes.

### When RedisInsight documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in RedisInsight change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting RedisInsight documentation.
