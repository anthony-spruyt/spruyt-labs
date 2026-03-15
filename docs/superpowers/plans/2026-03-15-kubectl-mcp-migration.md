# Kubernetes MCP Migration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate agents and Claude rules from raw `kubectl` to kubernetes MCP server tools, with fallback to kubectl when MCP is unavailable.

**Architecture:** Add a new rule file (`.claude/rules/07-mcp-kubernetes.md`) as the authoritative reference for MCP tool mappings and fallback behavior. Update CLAUDE.md with a quick-reference row and Hard Rule #2 clarification. Update 5 agent system prompts to reference MCP tools and add `mcpServers: ["kubernetes"]` frontmatter. Expand kubectl-mcp-server RBAC for write operations.

**Tech Stack:** Kubernetes MCP server (in-cluster), Claude Code agents, YAML manifests

**Spec:** `docs/superpowers/specs/2026-03-15-kubectl-mcp-migration-design.md`

---

## Chunk 1: Rules and CLAUDE.md

### Task 1: Create `.claude/rules/07-mcp-kubernetes.md`

**Files:**
- Create: `.claude/rules/07-mcp-kubernetes.md`

- [ ] **Step 1: Create the rule file**

```markdown
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
| `hubble observe` | `hubble_flows_query_tool` |

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
| `kubectl port-forward` | Long-running session, may time out via MCP |

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

MCP write tools (patch, delete, scale, restart, node_management) are permitted for **operational tasks** only:
- Incident response (restart pods, scale deployments)
- Node management (cordon, drain, taint)
- Pod cleanup (delete failed/completed pods)

MCP write tools must NOT be used for declarative config changes -- use Flux/GitOps instead.
```

- [ ] **Step 2: Verify the file renders correctly**

Read the file back and check formatting.

- [ ] **Step 3: Commit**

```bash
git add .claude/rules/07-mcp-kubernetes.md
git commit -m "feat(rules): add kubernetes MCP tool preference rule"
```

### Task 2: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md:44-50` (Tool Usage table)
- Modify: `CLAUDE.md:22` (Hard Rule #2)

- [ ] **Step 1: Add row to Tool Usage table**

After the `List env keys` row (line 50), add:

```markdown
| Kubernetes ops | `mcp__kubernetes__*` tools | `kubectl` (fallback only) |
```

- [ ] **Step 2: Clarify Hard Rule #2**

Change line 22 from:
```
2. **Declarative only** - No manual kubectl patches; use Flux, Terraform, Talos configs
```
To:
```
2. **Declarative only** - No manual kubectl patches for config changes; use Flux, Terraform, Talos configs. Operational commands (restart, scale, drain) via MCP tools are permitted.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude): add MCP tool preference and clarify Hard Rule 2"
```

### Task 3: Update `05-procedures.md`

**Files:**
- Modify: `.claude/rules/05-procedures.md:50-52` (Error Recovery section)

- [ ] **Step 1: Update the RBAC check command**

Change the Error Recovery section (lines 50-52) from:
```bash
# RBAC issues
kubectl auth can-i <verb> <resource>
```
To:
```bash
# RBAC issues (prefer MCP: mcp__kubernetes__audit_rbac_permissions)
kubectl auth can-i <verb> <resource>
```

- [ ] **Step 2: Commit**

```bash
git add .claude/rules/05-procedures.md
git commit -m "docs(rules): add MCP alternative note to RBAC check"
```

### Task 4: Update `06-ingress-and-certificates.md`

**Files:**
- Modify: `.claude/rules/06-ingress-and-certificates.md:57-62` (Validation section)

- [ ] **Step 1: Update validation commands**

Change the Validation section (lines 57-62) from:
```markdown
## Validation

```bash
kubectl get ingressroute -A          # All routes
kubectl get certificates -A          # All certs (check Ready=True)
```
```

To:
```markdown
## Validation

Prefer MCP tools: `mcp__kubernetes__list_custom_resources` (IngressRoutes), `mcp__kubernetes__certs_list_tool` (Certificates).

Fallback:
```bash
kubectl get ingressroute -A          # All routes
kubectl get certificates -A          # All certs (check Ready=True)
```
```

- [ ] **Step 2: Commit**

```bash
git add .claude/rules/06-ingress-and-certificates.md
git commit -m "docs(rules): add MCP tool preference for ingress/cert validation"
```

---

## Chunk 2: Agent Updates

### Task 5: Update `cluster-validator.md`

**Files:**
- Modify: `.claude/agents/cluster-validator.md`

- [ ] **Step 1: Add `mcpServers` to frontmatter**

Add `mcpServers: ["kubernetes"]` to the YAML frontmatter (after the `tools:` block, before the closing `---`).

Also add `Write` to the tools list (needed for agent memory pattern file updates -- already used by agent but may be missing).

- [ ] **Step 2: Add MCP Tools section**

Add after the frontmatter, before the first heading:

```markdown
## Kubernetes MCP Tools

Prefer `mcp__kubernetes__*` MCP tools over raw `kubectl` for all cluster operations.
Fall back to `kubectl` only if MCP tools are unavailable or erroring.

Key mappings:
- `kubectl get nodes` -> `get_nodes`
- `kubectl get pods -n <ns>` -> `get_pods`
- `kubectl get events` -> `get_events`
- `kubectl get endpoints` -> `get_endpoints`
- `kubectl logs` -> `get_logs`
- `kubectl wait` -> `wait_for_condition`
- `kubectl create job` -> keep as kubectl (no direct MCP equivalent)
- `kubectl delete job` -> `delete_resource`
- `hubble observe --verdict DROPPED` -> `hubble_flows_query_tool`
```

- [ ] **Step 3: Replace kubectl commands in the agent body**

Replace each kubectl command with its MCP equivalent in the operational sections. Keep kubectl as a commented fallback where the command is complex. Specific replacements:

| Line | Current | Replacement |
|------|---------|-------------|
| ~58 | `kubectl get nodes` | `Use mcp__kubernetes__get_nodes` |
| ~61 | `kubectl get pods -n <namespace> -o wide` | `Use mcp__kubernetes__get_pods namespace=<namespace>` |
| ~62 | `kubectl get events -n <namespace>` | `Use mcp__kubernetes__get_events namespace=<namespace>` |
| ~63 | `kubectl get endpoints -n <namespace>` | `Use mcp__kubernetes__get_endpoints namespace=<namespace>` |
| ~87 | `kubectl wait --for=condition=Ready` | `Use mcp__kubernetes__wait_for_condition` |
| ~153 | `kubectl logs -n <namespace>` | `Use mcp__kubernetes__get_logs` |
| ~168 | `kubectl get cronjobs` | `Use mcp__kubernetes__get_jobs` (or keep kubectl for cronjob listing) |
| ~171 | `kubectl create job` | Keep as kubectl (job creation from cronjob template) |
| ~174 | `kubectl wait --for=condition=complete job` | `Use mcp__kubernetes__wait_for_condition` |
| ~177 | `kubectl logs job/<name>` | `Use mcp__kubernetes__get_logs` |
| ~180 | `kubectl delete job` | `Use mcp__kubernetes__delete_resource` |

For `hubble observe` (line ~41), replace with `mcp__kubernetes__hubble_flows_query_tool`.

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/cluster-validator.md
git commit -m "feat(agents): migrate cluster-validator to kubernetes MCP tools"
```

### Task 6: Update `cnp-drop-investigator.md`

**Files:**
- Modify: `.claude/agents/cnp-drop-investigator.md`

- [ ] **Step 1: Update frontmatter**

Change `mcpServers: victoriametrics` to `mcpServers: ["victoriametrics", "kubernetes"]`.

- [ ] **Step 2: Add MCP Tools section**

Add after the frontmatter:

```markdown
## Kubernetes MCP Tools

Prefer `mcp__kubernetes__*` MCP tools over raw `kubectl` for all cluster operations.
Fall back to `kubectl` only if MCP tools are unavailable or erroring.

Key mappings:
- `kubectl get ciliumnetworkpolicy` -> `cilium_policies_list_tool`
- `kubectl get pods` -> `get_pods`
- `kubectl logs` -> `get_logs`
- `hubble observe --verdict DROPPED` -> `hubble_flows_query_tool`
```

- [ ] **Step 3: Replace kubectl commands in the agent body**

| Line | Current | Replacement |
|------|---------|-------------|
| ~30 | `kubectl get ciliumnetworkpolicy -n <namespace>` | `Use mcp__kubernetes__cilium_policies_list_tool` |
| ~31 | `kubectl get pods -n <namespace> --show-labels` | `Use mcp__kubernetes__get_pods namespace=<namespace>` |
| ~71 | `kubectl logs -n <namespace> -l app.kubernetes.io/name=<app>` | `Use mcp__kubernetes__get_logs` |

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/cnp-drop-investigator.md
git commit -m "feat(agents): migrate cnp-drop-investigator to kubernetes MCP tools"
```

### Task 7: Update `etcd-maintenance.md`

**Files:**
- Modify: `.claude/agents/etcd-maintenance.md`

- [ ] **Step 1: Update frontmatter**

Add `mcpServers: ["kubernetes"]` to the frontmatter.

- [ ] **Step 2: Add MCP Tools section**

Add after the frontmatter:

```markdown
## Kubernetes MCP Tools

Prefer `mcp__kubernetes__*` MCP tools over raw `kubectl` for all cluster operations.
Fall back to `kubectl` only if MCP tools are unavailable or erroring.

Key mappings:
- `kubectl get nodes` -> `get_nodes`
```

- [ ] **Step 3: Replace kubectl command**

| Line | Current | Replacement |
|------|---------|-------------|
| ~25 | `kubectl get nodes -l node-role.kubernetes.io/control-plane` | `Use mcp__kubernetes__get_nodes (filter for control-plane role in results)` |

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/etcd-maintenance.md
git commit -m "feat(agents): migrate etcd-maintenance to kubernetes MCP tools"
```

### Task 8: Update `talos-upgrade.md`

**Files:**
- Modify: `.claude/agents/talos-upgrade.md`

This agent has the most kubectl references (24). Many are `kubectl exec` into Ceph toolbox (keep as-is) and `kubectl get nodes` variants (migrate to MCP).

- [ ] **Step 1: Update frontmatter**

Add `mcpServers: ["kubernetes"]` to the frontmatter.

- [ ] **Step 2: Add MCP Tools section**

Add after the frontmatter:

```markdown
## Kubernetes MCP Tools

Prefer `mcp__kubernetes__*` MCP tools over raw `kubectl` for all cluster operations.
Fall back to `kubectl` only if MCP tools are unavailable or erroring.

Key mappings:
- `kubectl get nodes` -> `get_nodes` / `get_nodes_summary`
- `kubectl get pods` -> `get_pods`
- `kubectl get deployment` -> `get_deployments`
- `kubectl get cronjob` -> `get_custom_resource` (batch/v1 CronJob)
- `kubectl create job --from=cronjob` -> keep as kubectl
- `kubectl wait --for=condition=Ready node` -> `wait_for_condition`
- `kubectl exec` (Ceph) -> keep as kubectl (exec exception)
```

- [ ] **Step 3: Replace kubectl commands in the agent body**

Replacements (keep `kubectl exec` for Ceph as-is):

| Line(s) | Current | Replacement |
|---------|---------|-------------|
| ~88, ~158, ~371 | `kubectl get nodes -o wide` | `Use mcp__kubernetes__get_nodes_summary` |
| ~90, ~218 | `kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath=...` | `Use mcp__kubernetes__get_nodes, filter control-plane` |
| ~94, ~318 | `kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath=...` | `Use mcp__kubernetes__get_nodes, filter workers` |
| ~257, ~336 | `kubectl wait --for=condition=Ready node/$NODE_NAME` | `Use mcp__kubernetes__wait_for_condition` |
| ~389 | `kubectl get deployment -n kube-system descheduler` | `Use mcp__kubernetes__get_deployments namespace=kube-system` |
| ~390 | `kubectl get cronjob -n kube-system descheduler` | `Use mcp__kubernetes__get_jobs namespace=kube-system` |
| ~396 | `kubectl get jobs -n kube-system \| grep descheduler` | `Use mcp__kubernetes__get_jobs namespace=kube-system` |
| ~399 | `kubectl get pods -A -o wide --watch` | Keep as kubectl (--watch is long-running) |
| ~410 | `kubectl get pods -A -o wide` | `Use mcp__kubernetes__get_pods` |

Lines with `kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph ...` (163, 291, 294, 346, 378, 509, 512): Keep as kubectl -- exec exception.

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/talos-upgrade.md
git commit -m "feat(agents): migrate talos-upgrade to kubernetes MCP tools"
```

### Task 9: Update `ceph-health-checker.md`

**Files:**
- Modify: `.claude/agents/ceph-health-checker.md`

Almost all kubectl usage is `kubectl exec` into Ceph toolbox -- only one is replaceable.

- [ ] **Step 1: Update frontmatter**

Add `mcpServers: ["kubernetes"]` to the frontmatter.

- [ ] **Step 2: Add MCP Tools section**

Add after the frontmatter:

```markdown
## Kubernetes MCP Tools

Prefer `mcp__kubernetes__*` MCP tools over raw `kubectl` for all cluster operations.
Fall back to `kubectl` only if MCP tools are unavailable or erroring.

Key mappings:
- `kubectl get deploy` -> `get_deployments`
- `kubectl exec` (Ceph) -> keep as kubectl (exec exception)
```

- [ ] **Step 3: Replace the one replaceable command**

| Line | Current | Replacement |
|------|---------|-------------|
| ~39 | `kubectl -n rook-ceph get deploy/rook-ceph-tools` | `Use mcp__kubernetes__get_deployments namespace=rook-ceph` |

All other kubectl commands (lines 50-94) are `kubectl exec` into the Ceph toolbox pod -- keep as-is.

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/ceph-health-checker.md
git commit -m "feat(agents): migrate ceph-health-checker to kubernetes MCP tools"
```

---

## Chunk 3: RBAC Expansion

### Task 10: Expand kubectl-mcp-server ClusterRole

**Files:**
- Modify: `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/rbac.yaml`

- [ ] **Step 1: Add write verbs to existing rules**

In the existing ClusterRole, update these rules:

Core API group (add `delete` to pods, `patch` to nodes):
```yaml
  - apiGroups: [""]
    resources:
      - pods
    verbs: ["get", "list", "watch", "delete"]
  - apiGroups: [""]
    resources:
      - nodes
    verbs: ["get", "list", "watch", "patch"]
```

Note: `nodes` is currently under the same rule as `pods` with other core resources. Split `pods` and `nodes` into separate rules so they can have different verbs. Keep all other core resources as read-only.

Apps API group (add `patch`):
```yaml
  - apiGroups: ["apps"]
    resources:
      - deployments
      - statefulsets
      - daemonsets
      - replicasets
    verbs: ["get", "list", "watch", "patch"]
```

Batch API group (add `create`, `delete`):
```yaml
  - apiGroups: ["batch"]
    resources:
      - jobs
      - cronjobs
    verbs: ["get", "list", "watch", "create", "delete"]
```

- [ ] **Step 2: Update README.md**

Update `cluster/apps/kubectl-mcp/kubectl-mcp-server/README.md` line 35 to reflect the expanded RBAC scope:

Change:
```
- **RBAC scope**: Read-only access to core resources, apps, batch, networking, storage, RBAC, metrics, and Flux CRDs (HelmReleases, Kustomizations, Sources)
```
To:
```
- **RBAC scope**: Read-only access to most resources. Write access: pods (delete), nodes (patch for cordon/drain/taint), apps (patch for restart/scale), batch jobs (create/delete for validation)
```

- [ ] **Step 3: Run qa-validator**

Run the qa-validator agent on the changed files before committing.

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/kubectl-mcp/kubectl-mcp-server/app/rbac.yaml cluster/apps/kubectl-mcp/kubectl-mcp-server/README.md
git commit -m "feat(kubectl-mcp): expand RBAC for MCP write operations"
```

---

## Chunk 4: Verification

### Task 11: Verify migration completeness

- [ ] **Step 1: Grep agents for remaining bare kubectl**

```bash
grep -n "kubectl" .claude/agents/cluster-validator.md .claude/agents/cnp-drop-investigator.md .claude/agents/etcd-maintenance.md .claude/agents/talos-upgrade.md .claude/agents/ceph-health-checker.md
```

Each remaining `kubectl` instance must be:
- A `kubectl exec` (exception)
- A `kubectl create job --from=cronjob` (no MCP equivalent)
- A `kubectl get pods -A -o wide --watch` (long-running watch, exception)
- A `kubectl --dry-run` reference (exception)
- Inside a fallback note

- [ ] **Step 2: Verify all agents have mcpServers**

```bash
grep -l "mcpServers" .claude/agents/cluster-validator.md .claude/agents/cnp-drop-investigator.md .claude/agents/etcd-maintenance.md .claude/agents/talos-upgrade.md .claude/agents/ceph-health-checker.md
```

Expected: all 5 files listed.

- [ ] **Step 3: Verify RBAC has write verbs**

```bash
grep -A2 "delete\|patch\|create" cluster/apps/kubectl-mcp/kubectl-mcp-server/app/rbac.yaml
```

- [ ] **Step 4: Run qa-validator on all changed files**

Run qa-validator agent targeting all modified files.

- [ ] **Step 5: Push and run cluster-validator**

After user pushes, run cluster-validator to confirm RBAC changes deployed correctly.
