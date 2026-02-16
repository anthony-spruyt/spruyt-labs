# API Deprecation Scanning Reference

## Overview

Before upgrading Kubernetes, scan the live cluster for resources using API versions that will be removed in the target version. This catches issues that dry-run may miss — particularly for resources managed by operators or created dynamically.

## Scanning Methods

### Method 1: Direct Resource Query

For each API being removed, query the cluster directly:

```bash
# Check if a specific deprecated API group/version has resources
kubectl get <resource>.<api-group> --all-namespaces 2>/dev/null

# Examples for common deprecations:
kubectl get flowschemas.flowcontrol.apiserver.k8s.io --all-namespaces 2>/dev/null
kubectl get prioritylevelconfigurations.flowcontrol.apiserver.k8s.io --all-namespaces 2>/dev/null
```

### Method 2: API Server Metrics

Check which API versions are actively being requested:

```bash
# Get API server metrics for deprecated API usage
# Look for requests to deprecated API groups
kubectl get --raw /metrics 2>/dev/null | grep apiserver_requested_deprecated_apis
```

The `apiserver_requested_deprecated_apis` metric tracks:
- `group`: API group
- `version`: API version
- `resource`: Resource type
- `removed_release`: K8s version where API will be removed

Filter for APIs removed in the target version:

```bash
kubectl get --raw /metrics 2>/dev/null | grep apiserver_requested_deprecated_apis | grep 'removed_release="<target-minor>"'
```

### Method 3: Audit Existing Manifests

Scan the git repository for deprecated API versions in manifests. **Use the Grep tool** (not bash grep) per CLAUDE.md tool usage rules:

```
Grep(pattern: "apiVersion: <deprecated-group>/<deprecated-version>", path: "cluster/", glob: "*.yaml")
```

This catches statically defined resources but misses dynamically generated ones (Helm templates, operators).

## Common API Deprecation Patterns

### Flow Control APIs
- `flowcontrol.apiserver.k8s.io/v1beta3` -> `flowcontrol.apiserver.k8s.io/v1` (removed in 1.32)

### Batch APIs
- `batch/v1beta1` CronJob -> `batch/v1` CronJob (removed in 1.25)

### Networking APIs
- `networking.k8s.io/v1beta1` Ingress -> `networking.k8s.io/v1` Ingress (removed in 1.22)

### RBAC APIs
- `rbac.authorization.k8s.io/v1beta1` -> `rbac.authorization.k8s.io/v1` (removed in 1.22)

### Storage APIs
- `storage.k8s.io/v1beta1` CSIDriver -> `storage.k8s.io/v1` CSIDriver (removed in 1.22)

**Note:** This list is not exhaustive. Always cross-reference with the target version's changelog (see `references/breaking-changes-lookup.md`).

## Scanning Procedure

1. **Identify removed APIs** from Phase 1 breaking changes research
2. **Run Method 2 first** (metrics) — fastest, covers dynamic usage
3. **Run Method 1** for each identified removed API — catches currently existing resources
4. **Run Method 3** (Grep tool) — catches manifest definitions
5. **Compile results** with namespace, resource name, and current API version

## Reporting Format

```
## API Compatibility Scan Results

### Resources Using Removed APIs (BLOCKING)
| Namespace | Resource | Kind | Current API | Required Migration |
|-----------|----------|------|-------------|-------------------|
| <ns> | <name> | <kind> | <old-api> | <new-api> |

### Resources Using Deprecated APIs (WARNING)
| Namespace | Resource | Kind | Current API | Removal Version |
|-----------|----------|------|-------------|-----------------|
| <ns> | <name> | <kind> | <old-api> | v<version> |

### Manifest Files Using Deprecated APIs
| File | API Version | Migration |
|------|-------------|-----------|
| <path> | <old-api> | <new-api> |

**Result:** PASS (no removed APIs in use) / BLOCK (removed APIs found — migrate before upgrading)
```

## Remediation

When deprecated APIs are found:

1. **For Helm-managed resources**: Update the Helm chart version or override `apiVersion` in values
2. **For Flux Kustomization resources**: Update the source manifest `apiVersion` field
3. **For operator-managed resources**: Upgrade the operator first (it should handle API migration)
4. **For static manifests**: Edit the YAML to use the new API version

After remediation, re-run the scan to confirm all issues are resolved.
