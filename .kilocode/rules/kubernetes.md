# kubernetes.md

Kubectl workflow guidelines for Spruyt-labs homelab engineers working with Kubernetes custom resources, Helm charts, and cluster-level specifications. Use this reference before making configuration changes.

## Why these steps matter

Verifying the API surface, specification, and live configuration keeps Talos-managed clusters consistent with Flux automation and prevents overwriting controller-managed fields. Reviewing upstream documentation surfaces breaking changes before they impact production workloads and provides reviewers with traceable evidence.

## Command reference

### List available resource types and API groups

```sh
kubectl api-resources
```

### Explain resource specification fields

```sh
kubectl explain <resource_type>[.<field_path>]
```

Use `--recursive` when you need to inspect nested fields.

### Retrieve the live manifest for inspection

```sh
kubectl get <resource_type> <resource_name> -n <namespace> -o yaml
```

### Validate chart or manifest documentation

Use approved Context7 libraries, cluster documentation, or vendor references to confirm values and defaults. Document the sources you review so reviewers can validate the same information.

## Error Handling Workflows

### Common kubectl command failures

#### 'forbidden' error

- **Check RBAC permissions**: Run `kubectl auth can-i <verb> <resource> --as=<user>` to verify permissions
- **Inspect ServiceAccount**: If using a service account, check `kubectl get serviceaccount <name> -n <namespace> -o yaml` for bound roles
- **Review ClusterRoleBindings**: Execute `kubectl get clusterrolebinding` and check for appropriate bindings

#### 'not found' error

- **Verify namespace**: Confirm namespace exists with `kubectl get namespaces | grep <namespace>`
- **Check resource spelling**: Use `kubectl api-resources` to list available resources and verify correct resource type
- **Validate resource name**: Run `kubectl get <resource_type> -n <namespace>` to list existing resources in the namespace

#### 'connection refused' error

- **Check cluster access**: Verify `kubectl cluster-info` returns cluster endpoint information
- **Test connectivity**: Run `kubectl get nodes` to confirm API server connectivity
- **Review kubeconfig**: Check `kubectl config current-context` and ensure correct context is active

## Related Rules

- [error_handling.md](error_handling.md) — systematic troubleshooting frameworks
- [shared-procedures.md](shared-procedures.md) — common operational patterns
