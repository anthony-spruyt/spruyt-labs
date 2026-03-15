# Kubernetes MCP Migration: Agents and Rules

## Summary

Migrate agents and Claude rules from raw `kubectl` commands to the in-cluster kubernetes MCP server (`mcp__kubernetes__*` tools) for all operations where MCP tools exist. Fall back to raw kubectl when MCP is unavailable.

## Motivation

The kubectl-mcp-server is deployed in-cluster with API key auth and CiliumNetworkPolicies. Using MCP tools instead of raw kubectl:

- Provides structured JSON responses instead of text parsing
- Centralizes RBAC through a single service account
- Enables consistent access patterns across agents
- Keeps kubectl as a fallback during incidents when MCP may be down

## Scope

### In Scope

- 5 agent system prompts: `cluster-validator`, `cnp-drop-investigator`, `etcd-maintenance`, `talos-upgrade`, `ceph-health-checker`
- 2 rule files: `05-procedures.md`, `06-ingress-and-certificates.md`
- Root `CLAUDE.md` tool usage table
- New rule file: `.claude/rules/mcp-kubernetes.md`
- kubectl-mcp-server RBAC expansion for write operations

### Out of Scope

- Human-facing docs (`docs/maintenance.md`, `docs/disaster-recovery.md`, `docs/bootstrap.md`) -- humans may prefer raw kubectl
- Taskfile scripts (`.taskfiles/kubectl/`) -- bash scripts, not agent context
- `flux` CLI commands -- separate tool, not kubectl
- `talosctl` commands -- separate tool, not kubectl
- `qa-validator` agent -- uses `kubectl --dry-run=client` and `kubectl kustomize` for validation (no MCP equivalent for dry-run)
- `ceph-health-checker` agent `kubectl exec` commands -- all Ceph operations require exec into rook-ceph-tools pod (exception category)

## Design

### 1. CLAUDE.md Tool Table

Add a row to the existing "Tool Usage" table:

```markdown
| Kubernetes ops | `mcp__kubernetes__*` tools | `kubectl` (fallback only) |
```

### 2. New Rule File: `.claude/rules/mcp-kubernetes.md`

Contains:

#### Priority Statement

> Always prefer `mcp__kubernetes__*` MCP tools over raw `kubectl` for cluster operations. Fall back to `kubectl` only when MCP tools are unavailable or erroring.

#### Tool Mapping Table

| kubectl Command | MCP Tool | Notes |
|----------------|----------|-------|
| `kubectl get pods` | `get_pods` | |
| `kubectl get nodes` | `get_nodes` | |
| `kubectl get events` | `get_events` | |
| `kubectl get endpoints` | `get_endpoints` | |
| `kubectl get services` | `get_services` | |
| `kubectl get deployments` | `get_deployments` | |
| `kubectl get statefulsets` | `get_statefulsets` | |
| `kubectl get daemonsets` | `get_daemonsets` | |
| `kubectl get configmaps` | `get_configmaps` | |
| `kubectl get ingress` | `get_ingress` | |
| `kubectl get namespaces` | `get_namespaces` | |
| `kubectl get pvc` | `get_pvcs` | |
| `kubectl get pv` | `get_persistent_volumes` | |
| `kubectl get hpa` | `get_hpa` | |
| `kubectl get pdb` | `get_pdb` | |
| `kubectl logs` | `get_logs` | |
| `kubectl logs --previous` | `get_previous_logs` | |
| `kubectl describe` | `kubectl_describe` | |
| `kubectl explain` | `kubectl_explain` | |
| `kubectl get secret` (metadata only) | `get_secrets` | Deferred -- RBAC currently excludes secrets (Trivy AVD-KSV-0041) |
| `kubectl get custom-resource` | `get_custom_resource` / `list_custom_resources` | For CRDs like CiliumNetworkPolicy, IngressRoute, Certificate |
| `kubectl api-resources` | `get_api_resources` | |
| `kubectl patch` | `kubectl_patch` | |
| `kubectl delete` | `delete_resource` | |
| `kubectl apply` | `kubectl_apply` | |
| `kubectl rollout restart` | `restart_deployment` | |
| `kubectl rollout` | `kubectl_rollout` | status, history, undo |
| `kubectl scale` | `scale_deployment` | |
| `kubectl cordon/drain/uncordon` | `node_management` | |
| `kubectl taint` | `taint_node` | |
| `kubectl auth can-i` | `audit_rbac_permissions` | |
| `kubectl top nodes` | `node_top_tool` / `get_node_metrics` | |
| `kubectl top pods` | `get_pod_metrics` | |
| `kubectl wait --for=condition` | `wait_for_condition` | |
| `kubectl cp` | `kubectl_cp` | |
| `kubectl port-forward` | `port_forward` | May time out for long sessions |
| `kubectl get pod events` | `get_pod_events` | Field-selector filtered |
| `kubectl get pod conditions` | `get_pod_conditions` | |
| `hubble observe` | `hubble_flows_query_tool` | Replaces Cilium Hubble CLI |
| `kubectl get nodes -o wide` | `get_nodes_summary` | |

#### Exceptions (Must Remain kubectl)

| Operation | Why |
|-----------|-----|
| `kubectl exec` (interactive/Ceph) | Requires pod exec context with side effects |
| `kubectl --dry-run=client` | Validation mode, no MCP equivalent |
| `kubectl kustomize` | Build tool, no MCP equivalent |
| `flux` CLI commands | Separate tool, not kubectl |
| `talosctl` commands | Separate tool, not kubectl |

#### Fallback Behavior

```text
1. Try MCP tool first
2. If MCP returns error or tool not found:
   a. If 403/permission denied -> flag to user: "kubectl-mcp-server RBAC may need updating"
   b. If connection error -> fall back to raw kubectl, note: "MCP unavailable, using kubectl fallback"
   c. If tool doesn't exist for this operation -> use kubectl directly
```

#### Secrets Constraint

MCP tools do NOT bypass the secrets rules in `01-constraints.md`. The same forbidden operations apply:
- Never use MCP tools to read secret values
- `get_secrets` returns metadata only
- All rules from `01-constraints.md` remain in effect

### 3. Agent Updates

Each agent gets a standardized section added to its system prompt:

```markdown
## Kubernetes MCP Tools

Prefer `mcp__kubernetes__*` MCP tools over raw `kubectl` for all cluster operations.
Fall back to `kubectl` only if MCP tools are unavailable or erroring.
```

Plus specific command replacements in their operational sections:

#### cluster-validator.md

| Current | Replacement |
|---------|-------------|
| `kubectl get nodes` | `mcp__kubernetes__get_nodes` |
| `kubectl get pods -n <ns>` | `mcp__kubernetes__get_pods` |
| `kubectl get events -n <ns>` | `mcp__kubernetes__get_events` |
| `kubectl get endpoints -n <ns>` | `mcp__kubernetes__get_endpoints` |
| `kubectl wait` | `mcp__kubernetes__wait_for_condition` |

#### cnp-drop-investigator.md

| Current | Replacement |
|---------|-------------|
| `kubectl get ciliumnetworkpolicy -n <ns>` | `mcp__kubernetes__list_custom_resources` or `mcp__kubernetes__cilium_policies_list_tool` |
| `kubectl get pods -n <ns>` | `mcp__kubernetes__get_pods` |
| `kubectl logs` | `mcp__kubernetes__get_logs` |

#### etcd-maintenance.md

| Current | Replacement |
|---------|-------------|
| `kubectl get nodes -l node-role.kubernetes.io/control-plane` | `mcp__kubernetes__get_nodes` |

#### talos-upgrade.md

| Current | Replacement |
|---------|-------------|
| `kubectl get nodes` | `mcp__kubernetes__get_nodes` |
| `kubectl get pods -A` | `mcp__kubernetes__get_pods` |

#### ceph-health-checker.md

| Current | Replacement |
|---------|-------------|
| `kubectl -n rook-ceph get deploy/rook-ceph-tools` | `mcp__kubernetes__get_deployments` |
| `kubectl exec` (Ceph commands) | Keep as-is (exec with side effects) |

### 4. Rule File Updates

#### 05-procedures.md

Update Error Recovery section:
- `kubectl auth can-i` -> note MCP alternative `audit_rbac_permissions`

#### 06-ingress-and-certificates.md

Update validation commands:
- `kubectl get ingressroute -A` -> `list_custom_resources` or `get_ingress`
- `kubectl get certificates -A` -> `certs_list_tool`

### 5. RBAC Expansion

The kubectl-mcp-server ClusterRole needs write verbs for operations agents will perform via MCP. Current state is read-only (`get`, `list`, `watch`).

#### New verbs needed

| API Group | Resources | Verbs to Add | Used By |
|-----------|-----------|-------------|---------|
| `""` (core) | `pods` | `delete` | cleanup_pods |
| `""` (core) | `nodes` | `patch` | node_management (cordon/uncordon/taint) -- high impact |
| `apps` | `deployments` | `patch` | restart_deployment, scale_deployment |
| `apps` | `statefulsets` | `patch` | scale |
| `apps` | `daemonsets` | `patch` | rollout restart |
| `batch` | `jobs` | `create`, `delete` | cluster-validator CronJob validation |

#### Deferred verbs (add only if needed)

| API Group | Resources | Verbs | Reason to Defer |
|-----------|-----------|-------|----------------|
| `""` (core) | `pods/exec` | `create` | Security concern -- exec is powerful, only add for concrete use case |
| `""` (core) | generic `create` | `create` | kubectl_apply needs broad create -- undermines GitOps model |
| `""` (core) | `secrets` | `get`, `list` | Only add if agents need secret metadata via MCP -- currently removed per Trivy AVD-KSV-0041 |

#### Security note

Write RBAC expands the blast radius of the MCP server. The server is protected by:
- API key auth via Traefik middleware
- CiliumNetworkPolicy restricting access to Traefik and OpenClaw only
- LAN-only ingress (no public exposure)

These controls mitigate the risk of expanded RBAC.

### 6. CLAUDE.md Hard Rule #2 Clarification

Hard Rule #2 says "Declarative only -- No manual kubectl patches; use Flux, Terraform, Talos configs." MCP write operations (patch, delete, scale, restart) are permitted for **operational tasks** (incident response, node management, pod cleanup) but NOT for declarative config changes. Add a clarifying note to the rule.

### 7. Agent Frontmatter

Agents that need kubernetes MCP tools must have the MCP server listed in their frontmatter. Add `mcpServers: ["kubernetes"]` (or append to existing list) for each updated agent.

## Implementation Order

1. Create `.claude/rules/07-mcp-kubernetes.md` (new rule file with tool mapping and fallback guidance)
2. Add CLAUDE.md tool table row and Hard Rule #2 clarification
3. Update 5 agent files (system prompts + frontmatter)
4. Update 2 rule files (`05-procedures.md`, `06-ingress-and-certificates.md`)
5. Expand kubectl-mcp-server RBAC (separate commit)
6. Validate with qa-validator and cluster-validator

## Verification

After implementation, verify:
1. Grep all agent files for bare `kubectl` commands -- each remaining instance must be in the documented exceptions list
2. All updated agents have `mcpServers: ["kubernetes"]` in frontmatter
3. RBAC ClusterRole has the new write verbs
4. qa-validator passes on all changed files
5. cluster-validator confirms RBAC changes deployed correctly

## Risks

| Risk | Mitigation |
|------|------------|
| MCP server down during incident | Fallback to raw kubectl documented in rule file |
| RBAC too broad | Start with minimal write verbs, expand as needed |
| Agent behavior regression | Agents still work with kubectl fallback |
| MCP tool returns different format than kubectl | Agents should handle structured JSON (MCP) not text parsing |
