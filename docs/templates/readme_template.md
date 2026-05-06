# [Component Name] - [Brief Description]

## Overview

[Brief description of the component, its purpose, and role in the homelab.]

## Prerequisites

- [List actual dependencies from ks.yaml dependsOn field]

<!-- OPTIONAL: Operations section — include when the component has non-obvious
     operational knowledge that can't be derived from reading manifests alone.
     Delete this section if not applicable.

     Good candidates:
     - Integration procedures (e.g., adding SSO, onboarding a new consumer)
     - Cross-component interaction patterns (e.g., secret sync, RBAC wiring)
     - Naming conventions or format requirements the component enforces
     - Workarounds for upstream bugs or limitations
     - Credential rotation or lifecycle procedures
     - File reference tables mapping concepts to manifest locations

     See authentik/README.md for a comprehensive example.
-->

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
