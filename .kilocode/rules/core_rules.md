# Core Rules for Spruyt-labs Homelab

## Purpose

This consolidated rule establishes the core operational standards, workflows, and constraints for the spruyt-labs homelab environment. It combines project context, Kubernetes operations, error handling, and automation constraints into a unified reference.

## Standards

### Environment Overview

- **Platform**: Talos Linux Kubernetes cluster deployed on bare metal hardware
- **Access**: No SSH access to Talos nodes; all administration via Talos APIs, `talosctl`, Flux, or Kubernetes resources
- **Infrastructure**: Cloud components managed through Terraform manifests in `infra/` directory
- **Configuration**: Talos machine configuration in `talos/` directory
- **Development Environment**: VS Code devcontainer with `kubectl`, `talosctl`, `talhelper`, `gh`, `terraform`, and Taskfile support

### Operational Principles

1. **Automation First**: Prefer Flux, Terraform, and Talos declarative configs over manual intervention
2. **Validation Required**: Always test changes with linting/validation before committing
3. **Taskfile Priority**: Use Taskfile tasks first for development operations
4. **No Python Scripts**: Python scripts are strictly prohibited for troubleshooting or automation
5. **MCP Integration**: Use Context7 libraries and MCP tools for documentation and information

### Prohibited Actions

- **No Python Scripts**: Agents must not create, use, or suggest Python scripts
- **No Manual Overrides**: Avoid manual changes that conflict with automated workflows
- **No Undocumented Changes**: All modifications must follow documented procedures

## Procedures

### Development Workflow

1. **Plan Changes**: Review relevant rules and documentation
2. **Use Taskfile**: Execute operations using `task` commands first
3. **Validate Assumptions**: Query live cluster state before applying changes
4. **Test Changes**: Run linting and validation after modifications

### Kubernetes Operations

#### Basic kubectl Commands

```sh
# List available resource types and API groups
kubectl api-resources

# Explain resource specification fields
kubectl explain <resource_type>[.<field_path>] --recursive

# Retrieve live manifest for inspection
kubectl get <resource_type> <resource_name> -n <namespace> -o yaml
```

#### Error Handling Workflows

**Permission denied/forbidden**:

- Check RBAC:

```bash
kubectl auth can-i <verb> <resource> --as=<user>
```

- Verify service accounts:

```bash
kubectl get serviceaccount <name> -n <namespace> -o yaml
```

- Review cluster role bindings:

```bash
kubectl get clusterrolebinding
```

**Resource not found**:

- Verify namespace:

```bash
kubectl get namespaces | grep <namespace>
```

- Check resource type:

```bash
kubectl api-resources | grep <type>
```

- List resources:

```bash
kubectl get <type> -n <namespace>
```

**Connection refused**:

- Check cluster access:

```bash
kubectl cluster-info
```

- Test connectivity:

```bash
kubectl get nodes
```

- Review kubeconfig:

```bash
kubectl config current-context
```

### Flux Operations

```sh
# Reconcile Kustomization
flux reconcile kustomization <name> --with-source

# Get Kustomization status
flux get kustomizations -n flux-system

# Get HelmRelease status
flux get helmreleases -n <namespace>

# Diff changes before apply
flux diff ks <name> --path=./path
flux diff hr <name> --namespace <namespace>
```

### Error Recovery Procedures

1. **Attempt least disruptive recovery first** (reconcile → rollback → manual intervention)
2. **Document all recovery actions and outcomes**
3. **Validate fixes before considering issues resolved**
4. **Escalate if automated recovery fails**

#### Rollback Steps

**Flux Kustomization**:

- Suspend:

```bash
flux suspend kustomization <name>
```

- Revert source commit
- Resume:

```bash
flux reconcile kustomization <name> --with-source
```

**Helm Release**:

- Execute:

```bash
helm rollback <release> <revision> -n <namespace>
```

- Verify:

```bash
helm status <release> -n <namespace>
```

**Manifest Reversion**:

- Apply previous:

```bash
kubectl apply -f <previous-manifest.yaml>
```

- Confirm:

```bash
kubectl get <resource> -n <namespace>
```

### MCP Integration Workflow

- **Primary MCP endpoint**: See `../mcp.json` for context7 server configuration
- **Documentation preference**: Use `resolve-library-id` and `get-library-docs` before manual searches
- **Citation requirements**: Record library ID, version, and usage details in change notes
- **Escalation path**: When MCP tools fail, escalate per error handling criteria

## Validation

### Change Validation Steps

1. **Run Linting**:

```bash
task dev-env:lint
```

2. **Format and Validate Terraform** (if Terraform changes made):

```bash
task terraform:fmt
task terraform:validate
```

3. **Test Functionality**: Verify changes work as expected
4. **Check Cluster State**:

```bash
kubectl get nodes
talosctl get members
```

5. **Review Automation**: Ensure Flux reconciliation continues properly
6. **Monitor Post-Change**: Check resource status and events

### Expected Outcomes

- Linting passes without errors
- Cluster remains healthy and stable
- Automation continues functioning
- Documentation accurately reflects current state
- All decision trees are syntactically valid

## Machine-Readable Elements

### Core Operations Decision Tree

```yaml
# Decision tree for core operations
start: "operation_needed"
nodes:
  operation_needed:
    question: "What type of operation is needed?"
    options:
      kubernetes_change: "Kubernetes manifest change"
      infrastructure_change: "Infrastructure change"
      documentation_change: "Documentation update"
      troubleshooting: "Issue troubleshooting"
      mcp_integration: "MCP documentation lookup"
  kubernetes_change:
    action: "Verify API compatibility, check live config, use Flux automation"
    next: "validate_change"
  infrastructure_change:
    action: "Use Terraform manifests in infra/ directory"
    next: "validate_change"
  documentation_change:
    action: "Follow documentation standards, run linting"
    next: "validate_change"
  troubleshooting:
    action: "Follow symptom-based diagnosis, query cluster state"
    next: "validate_change"
  mcp_integration:
    action: "Check context7-libraries.json, use resolve-library-id if needed"
    next: "validate_change"
  validate_change:
    action: "Run task dev-env:lint, verify cluster health"
    next: "change_successful"
  change_successful:
    question: "Change successful?"
    yes: "commit_change"
    no: "troubleshoot_issue"
  troubleshoot_issue:
    action: "Follow error handling procedures"
    next: "retry_or_escalate"
  retry_or_escalate:
    question: "Retry or escalate?"
    options:
      retry: "operation_needed"
      escalate: "end"
  commit_change:
    action: "Commit with proper validation documentation"
    next: "end"
end: "end"
```

### Troubleshooting Decision Tree

```yaml
# Decision tree for operational issue diagnosis
start: "symptom_observed"
nodes:
  symptom_observed:
    question: "What type of symptom is observed?"
    options:
      kubectl_error: "kubectl command failure"
      flux_error: "Flux reconciliation issue"
      helm_error: "Helm release failure"
      pod_error: "Pod health/crash issue"
      python_suggested: "Python script suggested"
  kubectl_error:
    question: "What kubectl error?"
    options:
      permission_denied: "Permission denied/forbidden"
      not_found: "Resource not found"
      connection_refused: "Connection refused"
  permission_denied:
    action: "Check RBAC permissions and service account bindings"
    next: "validate_fix"
  not_found:
    action: "Verify namespace, resource type, and existing resources"
    next: "validate_fix"
  connection_refused:
    action: "Check cluster connectivity and kubeconfig context"
    next: "validate_fix"
  flux_error:
    question: "What Flux issue?"
    options:
      kustomization_stuck: "Kustomization stuck"
      helmrelease_failed: "HelmRelease failed"
      source_sync_error: "Source sync error"
  kustomization_stuck:
    action: "Check status, reconcile manually, verify source access"
    next: "validate_fix"
  helmrelease_failed:
    action: "Get status, diff changes, check chart dependencies"
    next: "validate_fix"
  source_sync_error:
    action: "Verify sources, check credentials and network"
    next: "validate_fix"
  pod_error:
    action: "Check pod logs, events, and describe output"
    next: "validate_fix"
  python_suggested:
    action: "Immediately reject, find approved alternative"
    next: "validate_fix"
  validate_fix:
    question: "Does fix resolve issue?"
    yes: "document_resolution"
    no: "escalate"
  document_resolution:
    action: "Record root cause, fix applied, and validation steps"
    next: "end"
  escalate:
    action: "Escalate to human operator per criteria"
    next: "end"
end: "end"
```

### Command Templates

```yaml
# Template for core operational commands
core_commands:
  validation:
    lint: "task dev-env:lint"
    cluster_health: "kubectl get nodes && talosctl get members"
    flux_status: "flux get kustomizations -A"
    kubectl_api: "kubectl api-resources"
    kubectl_explain: "kubectl explain <resource> --recursive"

  troubleshooting:
    kubectl_permissions: "kubectl auth can-i <verb> <resource>"
    kubectl_resources: "kubectl get <type> -n <namespace>"
    flux_reconcile: "flux reconcile kustomization <name> --with-source"
    helm_rollback: "helm rollback <release> <revision> -n <namespace>"

  mcp_integration:
    check_catalog: "grep -i '<topic>' ../context7-libraries.json"
    resolve_library: 'use_mcp_tool server_name=context7 tool_name=resolve-library-id arguments={"description": "<precise>"}'
    get_docs: 'use_mcp_tool server_name=context7 tool_name=get-library-docs arguments={"library_id": "<id>"}'
```

## Enforcement

- **Mandatory Linting**: All changes must pass `task dev-env:lint` before commit
- **Terraform Standards**: Format and validate all Terraform changes using `task terraform:fmt` and `task terraform:validate`
- **Python Prohibition**: Code review must reject any Python scripts
- **Documentation Requirements**: All components must have README.md files
- **Validation Requirements**: All decision trees must pass YAML syntax validation
- **Automation Compliance**: Changes must align with Flux/Terraform automation

## Related Rules

- [documentation_rules.md](documentation_rules.md) — documentation quality and structure standards
- [procedures.md](procedures.md) — detailed operational procedures and templates
- [renovate.md](renovate.md) — Renovate configuration management standards
- `../context7-libraries.json` — catalog of approved Context7 libraries
- `../mcp.json` — MCP server definitions and tool allowances
