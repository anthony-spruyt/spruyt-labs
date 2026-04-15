# ssh-key-rotation — Coder SSH signing key rotation

## Overview

Weekly CronJob that rotates the `coder-ssh-signing-key` Secret used by Coder
workspaces for Git SSH auth. Formerly colocated under `coder/app/`; relocated
to its own top-level app (parallels `coder-template-sync/`) so it has an
independent Flux Kustomization and lifecycle.

> **Note**: No HelmRelease — this is a Kustomize-only component.

## Prerequisites

- `coder` Kustomization deployed (dependsOn) — provides the `coder-ssh-signing-key` Secret the CronJob patches.
- Image `ghcr.io/anthony-spruyt/ssh-key-rotation` published.

## Operation

```bash
# Trigger manual rotation
kubectl -n coder-system create job \
  --from=cronjob/ssh-key-rotation ssh-rotation-smoke-test

# Inspect status
kubectl -n coder-system get cronjob ssh-key-rotation
kubectl -n coder-system logs -l app=ssh-key-rotation

# Reconcile
flux reconcile kustomization ssh-key-rotation --with-source
```

## Troubleshooting

1. **Job fails patching Secret**
   - **Symptom**: `secrets "coder-ssh-signing-key" forbidden`.
   - **Resolution**: Verify the `ssh-key-rotation` Role grants `get, patch` on that Secret and the RoleBinding targets the ServiceAccount.

2. **NetworkPolicy drops egress**
   - **Symptom**: Job logs `connection refused` to kube-apiserver or GitHub.
   - **Resolution**: Egress CNPs live in `app/network-policy.yaml` (`allow-ssh-rotation-*`). Confirm the pod label `app: ssh-key-rotation` still matches.

## References

- [Coder SSH keys](https://coder.com/docs/admin/external-auth)
