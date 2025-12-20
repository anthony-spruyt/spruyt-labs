# [Component Name] - [Brief Description]

## Overview

[Brief description of the component, its purpose, and role in the homelab.]

> **Note**: HelmRelease resources are managed by Flux in flux-system namespace but deploy workloads to the target namespace specified in ks.yaml.

## Prerequisites

- Kubernetes cluster with Flux CD
- [List actual dependencies from ks.yaml dependsOn field]

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n [namespace]
flux get helmrelease -n flux-system [component]

# Force reconcile (GitOps approach)
flux reconcile kustomization [component] --with-source

# View logs
kubectl logs -n [namespace] -l app.kubernetes.io/name=[component]
```

## Troubleshooting

### Common Issues

1. **[Issue description]**
   - **Symptom**: [What you observe]
   - **Resolution**: [How to fix - prefer editing manifests and reconciling over manual kubectl]

## References

- [Official Documentation](https://docs.example.com)

---

<!--
TEMPLATE USAGE NOTES (delete this section when using):
- Replace all [bracketed] placeholders with actual values
- Verify namespace matches ks.yaml targetNamespace
- Verify component name matches release.yaml metadata.name
- List actual dependencies from ks.yaml spec.dependsOn
- Test all commands before documenting
-->
