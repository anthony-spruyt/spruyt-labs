# [Component] - [One-line purpose]

## Overview

[1-3 sentences: what it does here and why it exists in this cluster. Not a product description.]

<!-- Every section below is OPTIONAL. Delete any without real content.
     Don't restate anything readable from ks.yaml / release.yaml / values.yaml. -->

## Prerequisites

<!-- Only what ks.yaml dependsOn can't express: Talos patches, Terraform, external accounts, one-time manual setup. -->

- [External prerequisite and where it lives]

## Operations

<!-- Non-obvious procedures: integrations, cross-component wiring, credential rotation, naming rules, workarounds.
     See cluster/apps/authentik-system/authentik/README.md for a good example. -->

## Troubleshooting

<!-- Only failures whose fix isn't obvious from the error. No generic kubectl/flux commands. -->

1. **[Symptom]**
   - **Cause**: [Why it happens]
   - **Fix**: [Prefer manifest change + reconcile over manual kubectl]

## References

- [Upstream docs](https://example.com)
