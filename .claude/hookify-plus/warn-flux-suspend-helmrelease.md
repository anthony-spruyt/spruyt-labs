---
name: warn-flux-suspend-helmrelease
enabled: true
event: bash
pattern: flux\s+(suspend|resume)\s+helmrelease
action: warn
warn_once: true
---

**WARNING: flux suspend/resume does NOT fix stuck HelmReleases**

**What to do instead:**

- Existing release with good revision: `helm rollback <release> <revision> -n <namespace>`
- New release (first install failed): `flux delete kustomization <name> -n flux-system` (Flux recreates on next reconciliation)
- **NEVER** delete kustomizations for stateful/critical infra (rook-ceph, volsync, cnpg, flux-system) — ask user first
