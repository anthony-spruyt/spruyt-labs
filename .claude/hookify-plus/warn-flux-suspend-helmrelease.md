---
name: warn-flux-stuck
enabled: true
event: bash
pattern: (flux\s+(suspend|resume)\s+helmrelease|flux\s+reconcile\s+kustomization|flux\s+reconcile\s+helmrelease)
action: warn
warn_once: true
---

**WARNING: flux suspend/resume and reconcile do NOT fix stuck HelmReleases**

**Symptoms of stuck release:**

- `flux get kustomization` shows old revision or "Reconciliation in progress" for >5m
- HelmRelease shows "Helm upgrade failed" with persistent error
- Pod rollout stalled (ImagePullBackOff, CrashLoopBackOff, ConfigMap/Secret not found)

**What to do instead:**

1. Check status: `flux get kustomization <name> -n flux-system` and `flux get helmrelease <name> -n <namespace>`
2. If kustomization stuck at stale revision: force reconcile with `kubectl -n flux-system annotate kustomization/<name> reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite`
3. If HelmRelease failed on existing release: `helm rollback <release> <last-good-revision> -n <namespace>`
4. If HelmRelease failed on first install: `flux delete kustomization <name> -n flux-system` (Flux recreates on next reconciliation)
5. **NEVER** delete kustomizations for stateful/critical infra (rook-ceph, volsync, cnpg, flux-system) — ask user first
