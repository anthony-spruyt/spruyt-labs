# Shared Procedures

## Purpose

Common operational patterns and procedures for spruyt-labs contributors.

## Standards

### Procedure Usage Guidelines

- Use established procedures for common operations to ensure consistency
- Document any deviations from standard procedures
- Update procedures when new patterns emerge or tools change

### Automation Preferences

- Prefer automated workflows over manual procedures
- Use Taskfile tasks for multi-step operations
- Document manual procedures only when automation is unavailable
- Regularly review procedures for automation opportunities

### Agentic Optimization Standards

1. **Standardized Decision Trees**: All procedures must include machine-readable decision trees with consistent structure
2. **Monitoring**: Include monitoring commands
3. **Cross-Service Mapping**: Document inter-service dependencies with health check commands
4. **MCP Integration**: Standardize Context7 library usage patterns and citation workflows

## Procedures

## Flux Operations

### Reconcile Kustomization

```sh
flux reconcile kustomization <name> --with-source
```

### Get Kustomization status

```sh
flux get kustomizations -n flux-system
```

### Get HelmRelease status

```sh
flux get helmreleases -n <namespace>
```

### Diff changes before apply

```sh
flux diff ks <name> --path=./path
flux diff hr <name> --namespace <namespace>
```

## Ingress and Certificate Management Procedures

### Choosing Between Internal (LAN) and External Access

- **Internal (LAN) Access**: Use for services intended only for local network access. Routes use `.lan.${EXTERNAL_DOMAIN}` domain suffix. No external DNS records are created. Suitable for administrative interfaces, monitoring tools, or services not exposed publicly.
- **External Access**: Use for services requiring public internet access. Routes use `${EXTERNAL_DOMAIN}` domain suffix. External DNS records are created for public resolution. Suitable for user-facing applications or APIs.

Consider security implications: external access requires proper authentication and authorization, while LAN access assumes network-level security.

### Creating Ingress Routes for New Workloads

When deploying applications requiring ingress routing, create Traefik IngressRoute resources for HTTPS routing. Choose between internal (LAN) or external access based on the guidance above.

#### For External Access (Public Internet)

1. Create `ingress-routes.yaml` in `cluster/apps/traefik/traefik/ingress/<workload>/` with the standard template:

   - Use `apiVersion: traefik.io/v1alpha1`, `kind: IngressRoute`
   - Set `entryPoints: [websecure]`
   - Configure `routes` with `Host(\`<workload>.${EXTERNAL_DOMAIN}\`)` match
   - Reference the workload service with correct port
   - Include `tls.secretName` pointing to the certificate secret
   - Add `external-dns.alpha.kubernetes.io/hostname: <workload>.${EXTERNAL_DOMAIN}` annotation

2. Add the file to `cluster/apps/traefik/traefik/ingress/kustomization.yaml` resources

3. Validate with `kubectl get ingressroute -n <namespace>` and test HTTPS access

#### For Internal Access (LAN Only)

1. Create `ingress-routes.yaml` in `cluster/apps/traefik/traefik/ingress/<workload>/` with the LAN template:

   - Use `apiVersion: traefik.io/v1alpha1`, `kind: IngressRoute`
   - Set `entryPoints: [websecure]`
   - Configure `routes` with `Host(\`<workload>.lan.${EXTERNAL_DOMAIN}\`)` match
   - Reference the workload service with correct port
   - Include `tls.secretName` pointing to the certificate secret
   - Add `external-dns.alpha.kubernetes.io/hostname: <workload>.lan.${EXTERNAL_DOMAIN}` annotation

2. Add the file to `cluster/apps/traefik/traefik/ingress/kustomization.yaml` resources

3. Validate with `kubectl get ingressroute -n <namespace>` and test HTTPS access via LAN

### Creating TLS Certificates for New Workloads

For secure HTTPS access, generate certificates using cert-manager. Create separate certificates for LAN and external access if both are needed.

#### For External Access Certificates

1. Create `certificates.yaml` in `cluster/apps/traefik/traefik/ingress/<workload>/` with the standard template:

   - Use `apiVersion: cert-manager.io/v1`, `kind: Certificate`
   - Set `secretName` to `<workload>-${EXTERNAL_DOMAIN/./-}-tls`
   - Reference `${CLUSTER_ISSUER}` as issuer
   - Include `dnsNames: ["<workload>.${EXTERNAL_DOMAIN}"]`

2. Add the file to `cluster/apps/traefik/traefik/ingress/kustomization.yaml` resources

3. Validate with `kubectl get certificates -n <namespace>` showing `Ready=True`

#### For Internal (LAN) Access Certificates

1. Create `certificates.yaml` in `cluster/apps/traefik/traefik/ingress/<workload>/` with the LAN template:

   - Use `apiVersion: cert-manager.io/v1`, `kind: Certificate`
   - Set `secretName` to `<workload>-lan-${EXTERNAL_DOMAIN/./-}-tls`
   - Reference `${CLUSTER_ISSUER}` as issuer
   - Include `dnsNames: ["<workload>.lan.${EXTERNAL_DOMAIN}"]`

2. Add the file to `cluster/apps/traefik/traefik/ingress/kustomization.yaml` resources

3. Validate with `kubectl get certificates -n <namespace>` showing `Ready=True`

### Validation Commands

- List all ingress routes

```bash
kubectl get ingressroute -A
```

- List all certificates

```bash
kubectl get certificates -A
```

- Check TLS secrets

```bash
kubectl get secrets -A | grep tls
```

## MCP Integration Workflow

### Server Configuration

The MCP server configuration is defined in `.kilocode/mcp.json`:

```json
{
  "mcpServers": {
    "context7": {
      "type": "streamable-http",
      "url": "https://mcp.context7.com/mcp",
      "alwaysAllow": ["resolve-library-id", "get-library-docs"],
      "headers": {
        "CONTEXT7_API_KEY": "${CONTEXT7_API_KEY}"
      }
    }
  }
}
```

### Security Considerations

- API keys are stored securely and not committed to version control
- `alwaysAllow` specifies pre-approved tools that don't require user confirmation
- All MCP operations are logged for audit purposes

### Usage Guidelines

- Primary MCP endpoint: see [`../mcp.json`](../mcp.json) for the `context7` server configuration.
- Before issuing `resolve-library-id`, consult the pre-approved catalog in [`context7-libraries.json`](../context7-libraries.json).
- When documentation is required, prefer MCP tools (`resolve-library-id`, `get-library-docs`) to ensure citations are consistent and cached.
- Record the library ID, version (if provided), and relevant snippets in your change notes or pull request description.
- If documentation is unavailable or outdated, escalate per the ownership guidance in the root README.md before proceeding.

### Tool Usage Guidelines

#### resolve-library-id

**Purpose**: Find the appropriate library ID for a given documentation topic

**Parameters**:

- `description`: Precise description of the documentation needed

**Usage**:

```bash
use_mcp_tool server_name=context7 tool_name=resolve-library-id arguments={"description": "Kubernetes Ingress API specification and usage"}
```

**Expected Output**: Library ID and metadata if match found

#### get-library-docs

**Purpose**: Retrieve documentation content from a specific library

**Parameters**:

- `library_id`: The library identifier (from catalog or resolve-library-id)
- `version`: Optional version specification

**Usage**:

```bash
use_mcp_tool server_name=context7 tool_name=get-library-docs arguments={"library_id": "kubernetes", "version": "v1.28"}
```

**Expected Output**: Documentation excerpts and metadata

### Decision Trees for Tool Selection

- **Use MCP tools first**: When documentation is required, always prefer `resolve-library-id` and `get-library-docs` over manual web searches to ensure consistent citations and cached results.
- **Escalate to human operators**: When MCP tools return no matches after precise queries, or when documentation gaps prevent autonomous resolution, involve human operators per escalation criteria in [`error_handling.md`](error_handling.md).
- **Manual searches as fallback**: Reserve ad-hoc web searches only when MCP servers are unavailable or when specific vendor documentation requires real-time access not covered by approved libraries.

## Context7 Library Usage

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../context7-libraries.json) to identify an existing entry that covers your topic.
- Confirm the catalog entry contains the documentation or API details you need before invoking any tools.
- Note the library identifier, source description, and any version information that appears in the catalog.

### When the catalog already covers your need

1. Use the information from [`context7-libraries.json`](../context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant citation details in your working notes, pull request description, or runbook draft.
3. Mention how the retrieved material informed your change (e.g., field defaults, API semantics, upgrade procedure).

### When the required library is missing or outdated

1. Run `resolve-library-id` with a precise description of the documentation you need.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update your worklog with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in your change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions you made when interpreting the documentation, especially when deviating from defaults.

### After your change

- Ensure the relevant rule or runbook references the same library ID so future contributors reuse consistent sources.
- If you discovered inaccuracies or stale references, open an issue or submit a follow-up change to update [`context7-libraries.json`](../context7-libraries.json) and the associated guidance.

### Troubleshooting Common Issues

1. **Library Not Found**:

   - Verify description precision in `resolve-library-id`
   - Check if topic is covered by existing libraries
   - Escalate if legitimate gap identified

2. **Server Connection Issues**:

   - Verify API key validity
   - Check network connectivity
   - Confirm server URL and configuration

3. **Documentation Quality Issues**:

   - Validate retrieved content against known sources
   - Report inaccuracies to documentation governance
   - Use alternative sources if Context7 content is outdated

4. **Citation Compliance**:
   - Ensure all citations include required metadata
   - Validate library IDs against catalog
   - Include usage context in documentation

### Validation Commands

```bash
# Validate MCP server connectivity
curl -H "CONTEXT7_API_KEY: <key>" https://mcp.context7.com/mcp

# Test library resolution
use_mcp_tool server_name=context7 tool_name=resolve-library-id arguments={"description": "test"}

# Validate catalog syntax
jq . .kilocode/context7-libraries.json

# Check library references in documentation
grep -r "context7-libraries.json" docs/
```

### Context7 Workflow Decision Tree

```yaml
# Decision tree for Context7 library usage
start: "documentation_needed"
nodes:
  documentation_needed:
    question: "Is documentation required for the task?"
    yes: "check_catalog"
    no: "end"
  check_catalog:
    question: "Does context7-libraries.json cover the needed documentation?"
    yes: "use_existing"
    no: "resolve_library"
  use_existing:
    action: "Use get-library-docs or direct catalog reference, record citation details"
    next: "document_change"
  resolve_library:
    action: "Run resolve-library-id with precise description"
    next: "library_found"
  library_found:
    question: "Did resolve-library-id return a match?"
    yes: "add_to_catalog"
    no: "escalate"
  add_to_catalog:
    action: "Add new library to context7-libraries.json, then use as existing"
    next: "document_change"
  escalate:
    action: "Escalate to documentation governance contact"
    next: "end"
  document_change:
    action: "Record library ID, version, and relevant snippets in change notes"
    next: "end"
end: "end"
```

### Context7 Command Templates

```yaml
# Template for Context7 tool usage
context7_commands:
  check_catalog: "grep -i '<topic>' ../context7-libraries.json"
  resolve_library: 'use_mcp_tool server_name=context7 tool_name=resolve-library-id arguments={"description": "<precise description>"}'
  get_docs: 'use_mcp_tool server_name=context7 tool_name=get-library-docs arguments={"library_id": "<id>", "version": "<version>"}'

# Template for citation recording
citation_template:
  library_id: "<resolved_id>"
  version: "<version_if_provided>"
  source: "Context7 MCP server"
  retrieved_at: "<timestamp>"
  used_for: "<change_description>"
```

## Standardized Agentic Workflow Patterns

### Standard Decision Tree Structure

```yaml
# Standard decision tree template for all procedures
start: "operation_start"
nodes:
  operation_start:
    question: "What operation is being performed?"
    options:
      deployment: "Component deployment"
      monitoring: "Performance monitoring"
      troubleshooting: "Issue resolution"
      maintenance: "Routine maintenance"
  deployment:
    action: "Follow deployment procedures with validation steps"
    next: "validate_deployment"
  monitoring:
    action: "Execute performance monitoring workflow"
    next: "analyze_metrics"
  troubleshooting:
    action: "Run diagnostic decision tree for issue"
    next: "identify_root_cause"
  maintenance:
    action: "Perform maintenance tasks with validation"
    next: "verify_maintenance"
  validate_deployment:
    question: "Deployment successful?"
    command: "kubectl get pods -n <namespace> --no-headers | grep 'Running'"
    yes: "operation_complete"
    no: "escalate_deployment"
  analyze_metrics:
    question: "Performance within thresholds?"
    command: "kubectl top pods -n <namespace> | awk '{print $3}' | head -1"
    yes: "operation_complete"
    no: "escalate_performance"
  identify_root_cause:
    question: "Root cause identified?"
    yes: "apply_fix"
    no: "escalate_diagnostics"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Issue resolved?"
    command: "kubectl get pods -n <namespace> --no-headers | grep 'Running'"
    yes: "operation_complete"
    no: "escalate_failure"
  verify_maintenance:
    question: "Maintenance completed successfully?"
    command: "kubectl get <resource> -n <namespace> --no-headers | grep 'Ready'"
    yes: "operation_complete"
    no: "escalate_maintenance"
  operation_complete:
    action: "Operation completed successfully"
    next: "end"
  escalate_deployment:
    action: "Escalate deployment failure with diagnostics"
    next: "end"
  escalate_performance:
    action: "Escalate performance issues with metrics"
    next: "end"
  escalate_diagnostics:
    action: "Escalate unresolved diagnostics"
    next: "end"
  escalate_failure:
    action: "Escalate fix failure with comprehensive logs"
    next: "end"
  escalate_maintenance:
    action: "Escalate maintenance issues"
    next: "end"
end: "end"
```

### Standard Performance Baseline Template

```yaml
# Standard performance baseline template
performance_baselines:
  response_time:
    threshold: "<X>ms"
    monitoring_command: "curl -w '%{time_total}' -o /dev/null -s <endpoint>"
  resource_usage:
    cpu:
      threshold: "<Y>%"
      monitoring_command: "kubectl top pods -n <namespace> --no-headers | awk '{print $3}'"
    memory:
      threshold: "<Z>Mi"
      monitoring_command: "kubectl top pods -n <namespace> --no-headers | awk '{print $4}'"
  availability:
    threshold: "99.9%"
    monitoring_command: "kubectl get <resource-type> -n <namespace> --no-headers | grep -c 'Running'"
```

### Standard Cross-Service Dependency Template

```yaml
# Cross-service dependency mapping template
service_dependencies:
  <component_name>:
    depends_on:
      - <dependency1>
      - <dependency2>
    depended_by:
      - <dependent1>
      - <dependent2>
    critical_path: true/false
    health_check_command: "kubectl get <resource-type> -n <namespace> <name>"
```

## Validation

### Procedure Validation Steps

1. **Execute Commands**: Run procedure commands in sequence
2. **Verify Outputs**: Check that each step produces expected results
3. **Test Functionality**: Confirm the procedure achieves its intended outcome
4. **Monitor for Issues**: Watch for errors or unexpected behavior
5. **Document Results**: Record validation outcomes and any issues encountered

### Expected Outcomes

- Commands execute successfully without errors
- Resources are created/modified as expected
- Services become available and functional
- No unexpected side effects occur
- Cluster remains stable throughout the procedure

## Machine-Readable Elements

### Decision Trees for Tool Selection

```yaml
# Decision tree for tool selection in procedures
start: "task_needed"
nodes:
  task_needed:
    question: "What type of task is needed?"
    options:
      documentation: "Documentation task"
      kubernetes_operation: "Kubernetes operation"
      ingress_setup: "Ingress/route setup"
      certificate_setup: "Certificate setup"
  documentation:
    question: "Documentation task type?"
    options:
      create_readme: "Create new README"
      update_readme: "Update existing README"
      validate_docs: "Validate documentation"
  create_readme:
    action: "Use documentation_rules.md procedures for creating README"
    next: "end"
  update_readme:
    action: "Use documentation_rules.md procedures for updating README"
    next: "end"
  validate_docs:
    action: "Run task dev-env:lint for validation"
    next: "end"
  kubernetes_operation:
    action: "Follow core_rules.md procedures and validation steps"
    next: "end"
  ingress_setup:
    question: "Ingress type?"
    options:
      external_access: "External (public) access"
      internal_access: "Internal (LAN) access"
  external_access:
    action: "Use external access procedures with .${EXTERNAL_DOMAIN} domain"
    next: "end"
  internal_access:
    action: "Use internal access procedures with .lan.${EXTERNAL_DOMAIN} domain"
    next: "end"
  certificate_setup:
    question: "Certificate type?"
    options:
      external_cert: "External access certificate"
      internal_cert: "Internal (LAN) access certificate"
  external_cert:
    action: "Create certificate with dnsNames for external domain"
    next: "end"
  internal_cert:
    action: "Create certificate with dnsNames for LAN domain"
    next: "end"
end: "end"
```

### Command Templates

```yaml
# Template for ingress route creation
ingress_route_commands:
  create_external: "Create ingress-routes.yaml with websecure entryPoints, Host(\`<workload>.${EXTERNAL_DOMAIN}\`) match, service reference, tls.secretName"
  create_internal: "Create ingress-routes.yaml with websecure entryPoints, Host(\`<workload>.lan.${EXTERNAL_DOMAIN}\`) match, service reference, tls.secretName"
  add_to_kustomization: "Add file to cluster/apps/traefik/traefik/ingress/kustomization.yaml resources"
  validate_route: "kubectl get ingressroute -n <namespace>"

# Template for certificate creation
certificate_commands:
  create_external: "Create certificates.yaml with apiVersion cert-manager.io/v1, secretName <workload>-${EXTERNAL_DOMAIN/./-}-tls, issuerRef ${CLUSTER_ISSUER}, dnsNames <workload>.${EXTERNAL_DOMAIN}"
  create_internal: "Create certificates.yaml with apiVersion cert-manager.io/v1, secretName <workload>-lan-${EXTERNAL_DOMAIN/./-}-tls, issuerRef ${CLUSTER_ISSUER}, dnsNames <workload>.lan.${EXTERNAL_DOMAIN}"
  add_to_kustomization: "Add file to cluster/apps/traefik/traefik/ingress/kustomization.yaml resources"
  validate_cert: "kubectl get certificates -n <namespace>, check Ready=True"
```

### Standardized Decision Tree Template

```yaml
# Standard decision tree template for all components
start: "operation_start"
nodes:
  operation_start:
    question: "What operation is being performed?"
    options:
      deployment: "Component deployment"
      monitoring: "Performance monitoring"
      troubleshooting: "Issue resolution"
      maintenance: "Routine maintenance"
  deployment:
    action: "Follow deployment procedures with validation steps"
    next: "validate_deployment"
  monitoring:
    action: "Execute performance monitoring workflow"
    next: "analyze_metrics"
  troubleshooting:
    action: "Run diagnostic decision tree for issue"
    next: "identify_root_cause"
  maintenance:
    action: "Perform maintenance tasks with validation"
    next: "verify_maintenance"
  validate_deployment:
    question: "Deployment successful?"
    command: "kubectl get pods -n <namespace> --no-headers | grep 'Running'"
    yes: "operation_complete"
    no: "escalate_deployment"
  analyze_metrics:
    question: "Performance within thresholds?"
    command: "kubectl top pods -n <namespace> | awk '{print $3}' | head -1"
    yes: "operation_complete"
    no: "escalate_performance"
  identify_root_cause:
    question: "Root cause identified?"
    yes: "apply_fix"
    no: "escalate_diagnostics"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Issue resolved?"
    command: "kubectl get pods -n <namespace> --no-headers | grep 'Running'"
    yes: "operation_complete"
    no: "escalate_failure"
  verify_maintenance:
    question: "Maintenance completed successfully?"
    command: "kubectl get <resource> -n <namespace> --no-headers | grep 'Ready'"
    yes: "operation_complete"
    no: "escalate_maintenance"
  operation_complete:
    action: "Operation completed successfully"
    next: "end"
  escalate_deployment:
    action: "Escalate deployment failure with diagnostics"
    next: "end"
  escalate_performance:
    action: "Escalate performance issues with metrics"
    next: "end"
  escalate_diagnostics:
    action: "Escalate unresolved diagnostics"
    next: "end"
  escalate_failure:
    action: "Escalate fix failure with comprehensive logs"
    next: "end"
  escalate_maintenance:
    action: "Escalate maintenance issues"
    next: "end"
end: "end"
```

### Performance Baseline Template

```yaml
# Standard performance baseline template
performance_baselines:
  response_time:
    threshold: "<X>ms"
    monitoring_command: "curl -w '%{time_total}' -o /dev/null -s <endpoint>"
  resource_usage:
    cpu:
      threshold: "<Y>%"
      monitoring_command: "kubectl top pods -n <namespace> --no-headers | awk '{print $3}'"
    memory:
      threshold: "<Z>Mi"
      monitoring_command: "kubectl top pods -n <namespace> --no-headers | awk '{print $4}'"
  availability:
    threshold: "99.9%"
    monitoring_command: "kubectl get <resource-type> -n <namespace> --no-headers | grep -c 'Running'"
```

### Cross-Service Dependency Template

```yaml
# Cross-service dependency mapping template
service_dependencies:
  <component_name>:
    depends_on:
      - <dependency1>
      - <dependency2>
    depended_by:
      - <dependent1>
      - <dependent2>
    critical_path: true/false
    health_check_command: "kubectl get <resource-type> -n <namespace> <name>"
```

## Related Rules

- [core_rules.md](core_rules.md) — kubectl workflow guidelines
- [documentation_rules.md](documentation_rules.md) — documentation quality standards
- [renovate.md](renovate.md) — Renovate configuration management standards
