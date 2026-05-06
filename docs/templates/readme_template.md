# [Component Name] - [Brief Description]

## Overview

[Brief description of the component, its purpose, and role in the homelab.]

> **Note**: HelmRelease resources are created in the target namespace specified by ks.yaml `targetNamespace`.

## Prerequisites

- Kubernetes cluster with Flux CD
- [List actual dependencies from ks.yaml dependsOn field]

## Troubleshooting

<!-- Only document non-obvious, component-specific issues. Do NOT add generic kubectl/flux commands. -->

1. **[Issue description]**
   - **Symptom**: [What you observe]
   - **Resolution**: [How to fix - prefer editing manifests and reconciling over manual kubectl]

## References

- [Official Documentation](https://docs.example.com)

______________________________________________________________________

<!--
TEMPLATE USAGE NOTES (delete this section when using):
- Replace all [bracketed] placeholders with actual values
- Verify namespace matches ks.yaml targetNamespace
- Verify component name matches release.yaml metadata.name
- List actual dependencies from ks.yaml spec.dependsOn
- Test all commands before documenting
-->
