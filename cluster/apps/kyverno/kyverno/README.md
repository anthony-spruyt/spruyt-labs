# kyverno - Policy Engine

## Overview

Admission controller for the cluster's mutating and validating policies (see [kyverno-policies](../policies/README.md)). Its webhooks use `failurePolicy: Fail`, so while the admission controller is down, create/update requests for matched resources are rejected cluster-wide.

## Operations

- **`kube-system` and `kyverno` are never mutated.** The chart excludes both from the webhooks to avoid a control-plane deadlock, so no policy - including the HelmRelease defaults - applies to resources there. Set fields explicitly.
- **`crdWatcher: true`** is what lets policies match CRD kinds such as `HelmRelease`; without it the webhook never registers them and CRD-targeted policies silently do nothing.
- **Cleanup controller RBAC**: `cleanupController.rbac.clusterRole.extraResources` grants pod `delete`. The chart does not, and `ClusterCleanupPolicy` objects that target pods (the agent pod cleanup) fail without it.

## Troubleshooting

1. **`admission webhook "validate-policy.kyverno.svc" denied the request` when changing a policy**
   - **Cause**: Some policy fields are immutable (for example generate rule targets).
   - **Fix**: Delete the ClusterPolicy and let Flux recreate it from Git.

## References

- [Kyverno documentation](https://kyverno.io/docs/)
