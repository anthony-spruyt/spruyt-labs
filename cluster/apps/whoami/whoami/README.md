# Whoami - Simple Identification Service

## Overview

Whoami is a simple HTTP service that returns information about the requesting client. In the spruyt-labs homelab infrastructure, Whoami serves as a lightweight testing and debugging tool for network connectivity, load balancing, and ingress routing verification.

## Directory Layout

```yaml
whoami/
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
- Network connectivity for HTTP traffic
- Ingress controller for external access
- Monitoring for service health
- Basic resource allocation

## Operation

### Procedures

1. **Service testing**:

   ```bash
   # Test service response
   kubectl exec -it <test-pod> -n whoami -- curl http://whoami.whoami.svc.cluster.local

   # Check response headers
   kubectl exec -it <test-pod> -n whoami -- curl -I http://whoami.whoami.svc.cluster.local
   ```

2. **Performance monitoring**:

   ```bash
   # Check service performance
   kubectl top pods -n whoami

   # Monitor request logs
   kubectl logs -n whoami <whoami-pod> | grep "request"
   ```

3. **Configuration updates**:

   ```bash
   # Update Whoami configuration
   kubectl apply -f values.yaml

   # Restart pods for configuration changes
   kubectl rollout restart deployment whoami -n whoami
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate service testing
kubectl exec -it <test-pod> -n whoami -- curl http://whoami.whoami.svc.cluster.local

# Expected: Service response

# Validate performance monitoring
kubectl top pods -n whoami

# Expected: Resource usage

# Validate configuration updates
kubectl get pods -n whoami --no-headers | grep 'Running'

# Expected: Pods running
```

### Decision Trees

```yaml
# Whoami operational decision tree
start: "whoami_health_check"
nodes:
  whoami_health_check:
    question: "Is Whoami healthy?"
    command: "kubectl get pods -n whoami --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "whoami_healthy"
  investigate_issue:
    action: "kubectl describe pods -n whoami | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      network_connectivity: "Network connectivity issue"
      resource_constraint: "Resource limitation"
      configuration_error: "Configuration mismatch"
      ingress_routing: "Ingress routing problem"
  network_connectivity:
    action: "Test network connectivity: kubectl exec -it <test-pod> -n whoami -- curl -v http://whoami:80"
    next: "apply_fix"
  resource_constraint:
    action: "Check resource usage: kubectl top pods -n whoami"
    next: "apply_fix"
  configuration_error:
    action: "Review values.yaml and service configuration"
    next: "apply_fix"
  ingress_routing:
    action: "Check ingress routes: kubectl get ingressroutes -A | grep whoami"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n whoami --no-headers | grep 'Running'"
    yes: "whoami_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  whoami_healthy:
    action: "Whoami verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# Whoami cross-service dependencies
service_dependencies:
  whoami:
    depends_on:
      - kube-system/cilium
      - observability/victoria-metrics-k8s-stack
      - traefik/traefik
    depended_by:
      - Network testing tools
      - Ingress verification services
      - Debugging and troubleshooting workflows
    critical_path: false
    health_check_command: "kubectl get pods -n whoami --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Connection failures**:

   - **Symptom**: Unable to reach Whoami service
   - **Diagnosis**: Check network connectivity and DNS
   - **Resolution**: Verify Cilium network policies and service discovery

2. **Response errors**:

   - **Symptom**: HTTP error responses
   - **Diagnosis**: Check service logs and configuration
   - **Resolution**: Verify service configuration and resource allocation

3. **Performance bottlenecks**:

   - **Symptom**: High latency or timeouts
   - **Diagnosis**: Monitor resource usage and request patterns
   - **Resolution**: Scale resources or optimize service configuration

4. **Ingress routing problems**:

   - **Symptom**: External access failures
   - **Diagnosis**: Check ingress routes and Traefik configuration
   - **Resolution**: Verify ingress routing and Traefik middleware

## Maintenance

### Updates

```bash
# Update Whoami using Flux
flux reconcile kustomization whoami --with-source

# Check update status
kubectl get helmreleases -n whoami
```

### Service Management

```bash
# Scale service
kubectl scale deployment whoami -n whoami --replicas=3

# Restart service
kubectl rollout restart deployment whoami -n whoami
```

### MCP Integration

- **Library ID**: `whoami-identification-service`
- **Version**: `v1.5.0`
- **Usage**: Simple HTTP identification service
- **Citation**: Use `resolve-library-id` for Whoami configuration

## References

- [Whoami Container](https://hub.docker.com/r/containous/whoami)
- [HTTP Testing Guide](https://developer.mozilla.org/en-US/docs/Web/HTTP)
- [Kubernetes Service Documentation](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Ingress Testing Patterns](https://kubernetes.io/docs/concepts/services-networking/ingress/)

## Agent-Friendly Workflows

### Whoami Health Check Workflow

```yaml
# Whoami health check decision tree
start: "check_whoami_pods"
nodes:
  check_whoami_pods:
    question: "Are Whoami pods running?"
    command: "kubectl get pods -n whoami --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_service_response"
    no: "restart_whoami_pods"
  check_service_response:
    question: "Is Whoami service responding?"
    command: "kubectl exec -n whoami deployment/whoami -- curl -s http://localhost:80 | grep -c 'RemoteAddr'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "NO_RESPONSE"}'' | grep -q ''OK'''
    yes: "check_ingress_access"
    no: "fix_service_config"
  check_ingress_access:
    question: "Is ingress access working?"
    command: "curl -s -k https://whoami.${EXTERNAL_DOMAIN} | grep -c 'RemoteAddr'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "INGRESS_FAIL"}'' | grep -q ''OK'''
    yes: "whoami_healthy"
    no: "fix_ingress_config"
  restart_whoami_pods:
    action: "Restart Whoami pods"
    next: "check_whoami_pods"
  fix_service_config:
    action: "Check and fix Whoami service configuration"
    next: "check_service_response"
  fix_ingress_config:
    action: "Check and fix ingress routing configuration"
    next: "check_ingress_access"
  whoami_healthy:
    action: "Whoami identification service is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for Whoami documentation.
- Confirm the catalog entry contains the documentation or API details needed for Whoami operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers Whoami documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed Whoami configuration changes.

### When Whoami documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in Whoami change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting Whoami documentation.
