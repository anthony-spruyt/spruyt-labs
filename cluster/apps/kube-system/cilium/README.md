# Cilium - Networking and Security

## Purpose and Scope

Cilium provides advanced networking, security, and observability for the spruyt-labs Kubernetes cluster using eBPF technology, serving as the primary CNI and network security solution.

Objectives:

- Provide high-performance CNI networking for Kubernetes workloads
- Implement network policies for microsegmentation and security
- Enable BGP routing for integration with external networks
- Provide load balancing capabilities for services
- Offer deep observability and monitoring of network traffic

## Overview

Cilium provides networking, security, and observability for Kubernetes using eBPF technology. It serves as the CNI (Container Network Interface) for the spruyt-labs cluster, providing network connectivity, load balancing, network policies, and security features.

## Directory Layout

```yaml
cilium/
├── app/
│   ├── bgp-advertisements.yaml      # BGP route advertisements
│   ├── bgp-cluster.yaml            # BGP cluster configuration
│   ├── bgp-peer.yaml               # BGP peer configuration
│   ├── cluster-lb-ip-pool.yaml     # Load balancer IP pool
│   ├── kustomization.yaml          # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Prerequisites

- Kubernetes cluster with Flux CD installed
- BGP-capable network infrastructure
- IPv4/IPv6 connectivity configured
- Node networking properly configured

### Validation

```bash
# Validate Cilium installation
kubectl get pods -n kube-system -l k8s-app=cilium

# Check Cilium status
cilium status

# Validate network connectivity
kubectl get nodes -o wide
```

## Operation

### Procedures

1. **Network policy management**:

```bash
# Apply network policy
kubectl apply -f network-policy.yaml

# Check network policies
kubectl get networkpolicies -A
```

2. **BGP monitoring**:

```bash
# Check BGP peer status
kubectl get bgppeers -n kube-system -o wide

# Check BGP advertisements
kubectl get bgpadvertisements -n kube-system
```

3. **Load balancer management**:

```bash
# Check load balancer services
kubectl get svc -A --field-selector spec.type=LoadBalancer

# Check load balancer IP allocation
kubectl get ciliumloadbalancerippools -n kube-system
```

### Decision Trees

```yaml
# Cilium operational decision tree
start: "cilium_health_check"
nodes:
  cilium_health_check:
    question: "Is Cilium healthy?"
    command: "kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "cilium_healthy"
  investigate_issue:
    action: "kubectl describe pods -n kube-system -l k8s-app=cilium | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      bgp_config_error: "BGP configuration problem"
      network_policy_conflict: "Network policy conflict"
      eBPF_loading_failure: "eBPF module loading failure"
      node_connectivity: "Node connectivity issue"
  bgp_config_error:
    action: "Check BGP configuration: kubectl get bgppeers -n kube-system -o yaml"
    next: "apply_fix"
  network_policy_conflict:
    action: "Review network policies: kubectl get networkpolicies -A -o yaml"
    next: "apply_fix"
  eBPF_loading_failure:
    action: "Check eBPF compatibility and node status"
    next: "apply_fix"
  node_connectivity:
    action: "Investigate node-to-node connectivity and MTU settings"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | grep 'Running'"
    yes: "cilium_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  cilium_healthy:
    action: "Cilium verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# Cilium cross-service dependencies
service_dependencies:
  cilium:
    depends_on:
      - kube-system/core-dns
      - traefik/traefik
    depended_by:
      - All workloads requiring network connectivity
      - All services requiring load balancing
      - All applications using network policies
    critical_path: true
    health_check_command: "kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **BGP session failures**:

   - **Symptom**: BGP peers not establishing sessions
   - **Diagnosis**: Check BGP configuration and peer reachability
   - **Resolution**: Verify BGP peer IP addresses and AS numbers

2. **Network policy enforcement issues**:

   - **Symptom**: Unexpected network connectivity
   - **Diagnosis**: Review network policy rules and labels
   - **Resolution**: Verify policy selectors and rule definitions

3. **eBPF loading failures**:
   - **Symptom**: Cilium pods failing to start
   - **Diagnosis**: Check kernel compatibility and eBPF support
   - **Resolution**: Verify node kernel version and eBPF requirements

## Maintenance

### Updates

```bash
# Update Cilium Helm chart
helm repo update
helm upgrade cilium cilium/cilium -n kube-system -f values.yaml
```

### BGP Management

```bash
# Update BGP configuration
kubectl apply -f updated-bgp-config.yaml

# Check BGP route advertisements
kubectl get bgpadvertisements -n kube-system -o wide
```

### Backups

```bash
# Backup Cilium configuration
kubectl get bgppeers -n kube-system -o yaml > cilium-bgp-peers-backup.yaml
kubectl get bgpadvertisements -n kube-system -o yaml > cilium-bgp-ads-backup.yaml
kubectl get ciliumnetworkpolicies -A -o yaml > cilium-network-policies-backup.yaml

# Restore from backup
kubectl apply -f cilium-bgp-peers-backup.yaml
kubectl apply -f cilium-bgp-ads-backup.yaml
kubectl apply -f cilium-network-policies-backup.yaml
```

### MCP Integration

- **Library ID**: `cilium`
- **Version**: `v1.15.5`
- **Usage**: Kubernetes networking, security, and observability
- **Citation**: Use `resolve-library-id` for Cilium configuration and troubleshooting

## References

- [Cilium Documentation](https://docs.cilium.io/)
- [eBPF Documentation](https://ebpf.io/)
- [BGP Configuration Guide](https://docs.cilium.io/en/stable/network/bgp/)

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of Cilium tasks.

### Network Health Check Workflow

```bash
If kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | grep -v 'Running' > /dev/null
Then:
  Run kubectl describe pods -n kube-system -l k8s-app=cilium
  Expected output: Pod details and events
  If events show connectivity issues:
    Run kubectl get ciliumnetworkpolicies -A
    Expected output: Network policy list
    Recovery: Review and adjust network policies
  Else:
    Proceed to next check
Else:
  Proceed to next check
```

## Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for Cilium documentation.
- Confirm the catalog entry contains the documentation or API details needed for Cilium operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers Cilium documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed Cilium configuration changes.

### When Cilium documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in Cilium change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting Cilium documentation.
