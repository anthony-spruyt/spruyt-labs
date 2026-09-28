# coder-template-sync - GitOps template sync for Coder

## Overview

Keeps Coder workspace templates in Git: a Job pushes every template under `app/templates/` to Coder as the `gitops-bot` headless user whenever a template file changes, and a CronJob keeps that user's session token alive. Kustomize-only; no HelmRelease.

## Prerequisites

- `gitops-bot` headless user in Coder with the `template-admin` site role (manual, one-time).
- A bootstrap session token for it in `app/secret-bootstrap.sops.yaml` (`coder-gitops-bot-token`, keys `token` and `token-id`).

## Operations

### How a change triggers a push

Template files are packed into the `coder-templates` ConfigMap with a hashed name. `app/kustomizeconfig.yaml` rewrites the Job's volume to that hashed name, so any template edit changes the Job spec. Job specs are immutable, so the Job carries `kustomize.toolkit.fluxcd.io/force: "Enabled"` (the value must be `Enabled`; `true` is ignored) and Flux deletes and recreates it (#966).

`ks.yaml` sets `substitution.flux.home.arpa/disabled: "true"` because HCL `${...}` interpolation cannot be escaped for Flux. **Do not use `${VAR}` Flux substitutions in this component.**

### Add a template

1. Create `app/templates/<name>/` with `main.tf` and `README.md`. The README is shown on the template page in the Coder UI, so write it for the person creating a workspace, keep it self-contained, and use absolute GitHub links; relative links and links to cluster-side docs are useless there.
2. Add each file to `configMapGenerator.files` in `app/kustomization.yaml` as `<name>__<file>=./templates/<name>/<file>` (ConfigMap keys cannot contain `/`).
3. Add a matching `items` entry to the `templates` volume in `app/job-template-push.yaml` mapping the key back to `<name>/<file>`. A file missing here is silently absent from the push.

### Token rotation

The CronJob `coder-token-rotation` mints a new 7-day token every 3 days and patches `coder-gitops-bot-token` in place. The bootstrap SOPS secret is only the seed, so after the first rotation the value in Git is stale by design.

Manual push, if the Job is broken: `coder templates push <name> --directory app/templates/<name> -y` as a template admin.

## Troubleshooting

1. **Rotation or push fails with `401 unauthorized`**

   - **Cause**: The live token expired (rotation missed for 7 days).
   - **Fix**: Create a new token for `gitops-bot` in Coder, update `app/secret-bootstrap.sops.yaml`, delete the live `coder-gitops-bot-token` Secret so Flux re-seeds it, then run the CronJob once.

2. **Template ConfigMap too large**

   - **Symptom**: Flux reports `ConfigMap ... is invalid` or `Request entity too large`.
   - **Cause**: ConfigMaps are capped at 1 MiB; the current templates total roughly 75 kB.
   - **Fix**: Move to a `GitRepository` source or an init container that clones at runtime.

3. **Push Job cannot reach Coder**

   - **Fix**: Check that the `coder-template-sync-egress` CNP selector still matches the Coder pod (`app.kubernetes.io/name: coder`) and that the matching `allow-template-sync-ingress` exists.

## References

- [Coder templates](https://coder.com/docs/admin/templates)
- [Coder long-lived tokens](https://coder.com/docs/admin/users/sessions-tokens)
- [Flux Kustomization apply behaviour](https://fluxcd.io/flux/components/kustomize/kustomizations/#controlling-the-apply-behavior-of-resources)
