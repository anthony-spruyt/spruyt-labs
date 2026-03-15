# Kubernetes MCP Tools

> **Always prefer `mcp__kubernetes__*` MCP tools over raw `kubectl` for cluster operations.**
> Fall back to `kubectl` only when MCP tools are unavailable or erroring.

## Tool Mapping

| kubectl Command | MCP Tool |
|----------------|----------|
| `kubectl get pods` | `get_pods` |
| `kubectl get nodes` | `get_nodes` / `get_nodes_summary` |
| `kubectl get events` | `get_events` / `get_pod_events` |
| `kubectl get endpoints` | `get_endpoints` |
| `kubectl get services` | `get_services` |
| `kubectl get deployments` | `get_deployments` |
| `kubectl get statefulsets` | `get_statefulsets` |
| `kubectl get daemonsets` | `get_daemonsets` |
| `kubectl get configmaps` | `get_configmaps` |
| `kubectl get ingress` | `get_ingress` |
| `kubectl get namespaces` | `get_namespaces` |
| `kubectl get pvc` | `get_pvcs` |
| `kubectl get pv` | `get_persistent_volumes` |
| `kubectl get hpa` | `get_hpa` |
| `kubectl get pdb` | `get_pdb` |
| `kubectl logs` | `get_logs` / `get_previous_logs` |
| `kubectl describe` | `kubectl_describe` |
| `kubectl explain` | `kubectl_explain` |
| `kubectl get <crd>` | `get_custom_resource` / `list_custom_resources` |
| `kubectl api-resources` | `get_api_resources` |
| `kubectl wait` | `wait_for_condition` |
| `kubectl top nodes` | `node_top_tool` / `get_node_metrics` |
| `kubectl top pods` | `get_pod_metrics` |
| `kubectl get pod conditions` | `get_pod_conditions` |
| `kubectl patch` | `kubectl_patch` |
| `kubectl delete` | `delete_resource` |
| `kubectl apply` | `kubectl_apply` |
| `kubectl rollout restart` | `restart_deployment` |
| `kubectl rollout` | `kubectl_rollout` |
| `kubectl scale` | `scale_deployment` |
| `kubectl cordon/drain/uncordon` | `node_management` |
| `kubectl taint` | `taint_node` |
| `kubectl auth can-i` | `audit_rbac_permissions` |
| `kubectl cp` | `kubectl_cp` |
| `kubectl port-forward` | `port_forward` |
| `hubble observe` | `hubble_flows_query_tool` |
| `kubectl get secret` (metadata) | `get_secrets` |

> **Note:** `get_secrets` is deferred -- RBAC currently excludes secrets (Trivy AVD-KSV-0041). `port_forward` may time out for long sessions; consider kubectl fallback for extended debugging.

### Cilium-Specific Tools

| kubectl/CLI Command | MCP Tool |
|---------------------|----------|
| `kubectl get ciliumnetworkpolicy` | `cilium_policies_list_tool` / `cilium_policy_get_tool` |
| `kubectl get ciliumendpoint` | `cilium_endpoints_list_tool` |
| `cilium status` | `cilium_status_tool` |
| `hubble observe --verdict DROPPED` | `hubble_flows_query_tool` |

### Cert-Manager Tools

| kubectl Command | MCP Tool |
|----------------|----------|
| `kubectl get certificates` | `certs_list_tool` |
| `kubectl get certificate <name>` | `certs_get_tool` |
| `kubectl get certificaterequest` | `certs_requests_list_tool` |
| `kubectl get issuer/clusterissuer` | `certs_issuers_list_tool` / `certs_issuer_get_tool` |

## Exceptions (Must Remain kubectl)

| Operation | Why |
|-----------|-----|
| `kubectl exec` | Pod exec with side effects (e.g., Ceph toolbox) |
| `kubectl --dry-run=client` | Validation mode, no MCP equivalent |
| `kubectl kustomize` | Build tool, no MCP equivalent |

`flux` and `talosctl` are separate tools -- not kubectl, not in scope.

## Fallback Behavior

1. Try MCP tool first
2. If MCP returns error or tool not found:
   - **403/permission denied** -> flag to user: "kubectl-mcp-server RBAC may need updating for `<resource>`"
   - **Connection error** -> fall back to raw kubectl, note: "MCP unavailable, using kubectl fallback"
   - **Tool doesn't exist** -> use kubectl directly

## Secrets Constraint

MCP tools do NOT bypass secrets rules in `01-constraints.md`. Never use MCP tools to read secret values. All existing secrets constraints remain in effect.

## Write Operations

MCP write operations are intentionally limited to minimize blast radius via OpenClaw:
- **Pod delete/eviction** -- cleanup failed pods, drain with PDB respect
- **Scale** (subresource only) -- adjust replicas on deployments/statefulsets

Operations requiring broad `patch` or `create` (restart, cordon/drain/taint, job creation) are NOT available via MCP. Agents fall back to local `kubectl` for these, which does not traverse OpenClaw.

MCP write tools must NOT be used for declarative config changes -- use Flux/GitOps instead.
