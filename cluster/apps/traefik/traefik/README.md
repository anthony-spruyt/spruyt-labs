# Traefik - Ingress Controller

## Overview

Traefik is a modern HTTP reverse proxy and load balancer that serves as the ingress controller for the spruyt-labs Kubernetes cluster. It provides routing, load balancing, TLS termination, and observability for all incoming traffic to the cluster.

## Directory Layout

```yaml
traefik/
├── app/
│   ├── kustomization.yaml            # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values
├── ingress/                        # Ingress route configurations
│   ├── kustomization.yaml          # Ingress kustomization
│   └── <workload>/                # Per-workload ingress routes
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Prerequisites

- Kubernetes cluster with Flux CD installed
- cert-manager deployed for TLS certificate management
- DNS properly configured for domains
- Load balancer IP addresses available

## Operation

### Procedures

1. **Ingress route management**:

```bash
# Add new ingress route
kubectl apply -f ingress/<workload>/ingress-route.yaml

# Check ingress route status
kubectl get ingressroutes -A -o wide
```

2. **TLS certificate monitoring**:

   ```bash
   # Check certificate status
   kubectl get certificates -A

   # Check certificate events
   kubectl get events -A | grep certificate
   ```

3. **Traefik dashboard access**:

```bash
# Access Traefik dashboard
kubectl port-forward svc/traefik -n traefik 9000:9000

# Check Traefik metrics
kubectl port-forward svc/traefik -n traefik 8082:8082
```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate ingress route management
kubectl get ingressroutes -A -o wide

# Expected: Ingress routes listed with status

# Validate TLS certificate monitoring
kubectl get certificates -A

# Expected: Certificates listed

# Validate Traefik dashboard access
kubectl port-forward svc/traefik -n traefik 9000:9000

# Expected: Port forward successful
```

### Decision Trees

```yaml
# Traefik operational decision tree
start: "traefik_health_check"
nodes:
  traefik_health_check:
    question: "Is Traefik healthy?"
    command: "kubectl get pods -n traefik --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "traefik_healthy"
  investigate_issue:
    action: "kubectl describe pods -n traefik | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      ingress_route_misconfig: "Ingress route misconfiguration"
      tls_cert_issue: "TLS certificate problem"
      load_balancer_failure: "Load balancer connectivity issue"
      resource_constraint: "Resource limitation"
  ingress_route_misconfig:
    action: "Check ingress route configuration: kubectl get ingressroutes -A -o yaml"
    next: "apply_fix"
  tls_cert_issue:
    action: "Verify TLS certificates: kubectl get certificates -A"
    next: "apply_fix"
  load_balancer_failure:
    action: "Check load balancer service and connectivity"
    next: "apply_fix"
  resource_constraint:
    action: "Adjust resource requests/limits in values.yaml"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n traefik --no-headers | grep 'Running'"
    yes: "traefik_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  traefik_healthy:
    action: "Traefik verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# Traefik cross-service dependencies
service_dependencies:
  traefik:
    depends_on:
      - cert-manager/cert-manager
      - kube-system/cilium
      - external-dns/external-dns-technitium
    depended_by:
      - All services requiring external access
      - All applications with ingress routes
      - All workloads needing TLS termination
    critical_path: true
    health_check_command: "kubectl get pods -n traefik --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Ingress route not working**:

   - **Symptom**: 404 errors on ingress routes
   - **Diagnosis**: Check ingress route configuration and service endpoints
   - **Resolution**: Verify route hostnames, service names, and ports

2. **TLS certificate errors**:

   - **Symptom**: Browser certificate warnings
   - **Diagnosis**: Check cert-manager certificate status
   - **Resolution**: Verify certificate DNS names and issuer configuration

3. **Load balancer connectivity issues**:
   - **Symptom**: External access failures
   - **Diagnosis**: Check load balancer service and Cilium BGP configuration
   - **Resolution**: Verify BGP advertisements and load balancer IP allocation

## Maintenance

### Updates

```bash
# Update Traefik Helm chart
helm repo update
helm upgrade traefik traefik/traefik -n traefik -f values.yaml
```

### Ingress Route Management

```bash
# Add new ingress route
kubectl apply -f ingress/<workload>/ingress-route.yaml

# Update existing ingress route
kubectl apply -f ingress/<workload>/updated-ingress-route.yaml
```

### MCP Integration

- **Library ID**: `traefik-ingress-controller`
- **Version**: `v2.10.5`
- **Usage**: Ingress routing and load balancing
- **Citation**: Use `resolve-library-id` for Traefik configuration and troubleshooting

## References

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [IngressRoute CRD Reference](https://doc.traefik.io/traefik/providers/kubernetes-crd/)
- [Traefik Helm Chart](https://github.com/traefik/traefik-helm-chart)

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of Traefik tasks.

### Traefik Health Check Workflow

```yaml
# Traefik health check decision tree
start: "check_traefik_pods"
nodes:
  check_traefik_pods:
    question: "Are Traefik pods running?"
    command: "kubectl get pods -n traefik --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_ingress_routes"
    no: "restart_traefik_pods"
  check_ingress_routes:
    question: "Are ingress routes configured correctly?"
    command: "kubectl get ingressroutes -A --no-headers | wc -l"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "NO_ROUTES"}'' | grep -q ''OK'''
    yes: "check_tls_certificates"
    no: "configure_ingress_routes"
  check_tls_certificates:
    question: "Are TLS certificates valid?"
    command: "kubectl get certificates -A --no-headers | grep -v 'True' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_load_balancer"
    no: "renew_certificates"
  check_load_balancer:
    question: "Is load balancer service healthy?"
    command: "kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress}' | wc -c"
    validation: 'awk ''{if ($1 > 2) print "OK"; else print "NO_LB"}'' | grep -q ''OK'''
    yes: "traefik_healthy"
    no: "fix_load_balancer"
  restart_traefik_pods:
    action: "Restart Traefik pods"
    next: "check_traefik_pods"
  configure_ingress_routes:
    action: "Configure missing ingress routes"
    next: "check_ingress_routes"
  renew_certificates:
    action: "Renew or fix TLS certificates"
    next: "check_tls_certificates"
  fix_load_balancer:
    action: "Fix load balancer configuration and connectivity"
    next: "check_load_balancer"
  traefik_healthy:
    action: "Traefik ingress controller is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for Traefik documentation.
- Confirm the catalog entry contains the documentation or API details needed for Traefik operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers Traefik documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed Traefik configuration changes.

### When Traefik documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in Traefik change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting Traefik documentation.
