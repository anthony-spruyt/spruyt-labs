# API Deprecation Scanning

## Scanning Methods

| Method | Command | Catches |
|--------|---------|---------|
| **Metrics** (run first) | `kubectl get --raw /metrics 2>/dev/null \| grep apiserver_requested_deprecated_apis \| grep 'removed_release="<minor>"'` | Dynamic usage from all clients |
| **Direct query** (per removed API) | `kubectl get <resource>.<api-group> --all-namespaces 2>/dev/null` | Currently existing resources |
| **Manifest scan** | Grep tool: `pattern: "apiVersion: <group>/<version>"` in `cluster/*.yaml` | Static definitions (misses Helm templates, operators) |

## Procedure

1. Identify removed APIs from Phase 1 breaking changes research
2. Run metrics method — fastest, covers dynamic usage
3. Run direct query for each identified removed API
4. Run manifest scan via Grep tool
5. Compile results: namespace, resource name, kind, current API version

## Remediation

| Resource Type | Fix |
|---------------|-----|
| Helm-managed | Update chart version or override `apiVersion` in values |
| Flux Kustomization | Update source manifest `apiVersion` field |
| Operator-managed | Upgrade operator first (handles API migration) |
| Static manifests | Edit YAML to use new API version |

Re-run scan after remediation to confirm all issues resolved.

## Output

Report as table with columns: Namespace, Resource, Kind, Current API, Required Migration. Separate BLOCKING (removed APIs) from WARNING (deprecated APIs). End with: PASS (no removed APIs in use) or BLOCK (removed APIs found).
