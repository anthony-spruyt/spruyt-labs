# error_handling.md

Systematic troubleshooting frameworks for spruyt-labs homelab engineers. This rule establishes structured approaches to diagnosing and resolving operational issues across Kubernetes, Flux, and Helm components.

## Symptom-Based Decision Trees

### Kubectl errors

- **Permission denied or forbidden**: Check RBAC with `kubectl auth can-i <verb> <resource> --as=<user>`; verify service account bindings; review cluster role bindings
- **Resource not found**: Confirm namespace exists with `kubectl get namespaces`; validate resource type via `kubectl api-resources`; list resources in namespace with `kubectl get <type> -n <namespace>`
- **Connection refused**: Verify cluster connectivity with `kubectl cluster-info`; test API server access with `kubectl get nodes`; check kubeconfig context with `kubectl config current-context`

### Flux reconciliation issues

- **Kustomization stuck**: Check status with `flux get kustomizations -n flux-system`; reconcile manually with `flux reconcile kustomization <name> --with-source`; review source repository access
- **HelmRelease failed**: Get status with `flux get helmreleases -n <namespace>`; diff changes with `flux diff hr <name> --namespace <namespace>`; check chart values and dependencies
- **Source sync errors**: Verify source status with `flux get sources -n flux-system`; check repository credentials and network connectivity

### Helm release failures

- **Chart installation timeout**: Check pod status with `kubectl get pods -n <namespace>`; review Helm history with `helm history <release> -n <namespace>`; examine release values
- **Dependency issues**: List dependencies with `helm dependency list <chart>`; verify chart repositories; check for conflicting resources
- **Upgrade failures**: Compare manifests with `helm diff upgrade <release> <chart> -n <namespace>`; rollback if necessary with `helm rollback <release> <revision> -n <namespace>`

## Escalation Criteria

Involve human operators when:

- Automated diagnostics fail to identify root cause after 3 attempts
- Issues impact production workloads with no clear recovery path
- Security-related failures requiring credential rotation or policy changes
- Infrastructure-level problems (network, storage, compute) beyond cluster scope
- Documentation gaps prevent autonomous resolution

## Recovery Procedures

### Rollback steps

1. **Flux Kustomization rollback**: Use `flux suspend kustomization <name>` to pause reconciliation; revert source commit; resume with `flux reconcile kustomization <name> --with-source`
2. **Helm release rollback**: Execute `helm rollback <release> <revision> -n <namespace>`; verify with `helm status <release> -n <namespace>`
3. **Manifest reversion**: Apply previous working manifest with `kubectl apply -f <previous-manifest.yaml>`; confirm with `kubectl get <resource> -n <namespace>`

### Log analysis commands

- **Pod logs**: `kubectl logs <pod-name> -n <namespace> --previous` for crashed containers; `kubectl logs <pod-name> -n <namespace> -f` for live streaming
- **Event inspection**: `kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp` for chronological event review
- **Flux logs**: `kubectl logs -n flux-system deployment/flux-controller` for reconciliation details
- **Helm debug**: `helm install --dry-run --debug <release> <chart> -n <namespace>` for validation without deployment
