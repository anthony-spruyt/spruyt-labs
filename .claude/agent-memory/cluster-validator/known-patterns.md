# Known Patterns

## Operational Patterns

Timing, behavioral, and environmental knowledge learned from validation runs.

| Pattern | Context | Count | Last Seen | Added |
|---------|---------|-------|-----------|-------|
| firemerge dependency chain (firefly-iii → firemerge → traefik-ingress) takes 3-5 min to fully reconcile | Full cluster reconciliation wait | 6 | 2026-03-03 | 2026-02-24 |
| flux-operator upgrade triggers FluxInstance re-reconciliation (~3s) and OutdatedVersion event for flux | Normal behavior after operator upgrade | 2 | 2026-02-28 | 2026-02-25 |
| authentik dependency chain (authentik → many apps → traefik-ingress) settles within ~90s | Full cluster reconciliation wait after flux-system changes | 7 | 2026-03-09 | 2026-02-25 |
| CronJob validation requires manual test job -- last completed job ran previous version | CronJob workload type detection | 2 | 2026-02-28 | 2026-02-28 |
| YAML comment-only changes (e.g., schema directives) reconcile instantly with no resource drift | Kustomize strips comments, producing identical output | 1 | 2026-03-01 | 2026-03-01 |
| n8n queue-mode deployment (main + worker + webhook) all roll simultaneously on image bump | HelmRelease values.yaml image tag change triggers rolling update of all 3 deployments | 2 | 2026-03-03 | 2026-03-03 |
| Large image first-pull (~1GB) can exceed 10m HelmRelease timeout; Flux auto-rollback then retries successfully with cached image | openclaw image update, image pulled in 10m1s exceeding timeout, auto-retry succeeded | 1 | 2026-03-09 | 2026-03-09 |
| Revert of failed kyverno policy change recovers full cluster within ~90s; Flux cleans up removed ClusterPolicy resources automatically | Revert commit after kyverno-policies reconciliation failure | 1 | 2026-03-09 | 2026-03-09 |

## Failure Signatures

Error patterns and their known resolutions.

| Error Pattern | Root Cause | Resolution | Count | Last Seen | Added |
|---------------|------------|------------|-------|-----------|-------|
| `exec: "/bin/sh": stat /bin/sh: no such file or directory` in CronJob pod | Scratch-based container image (e.g., `ghcr.io/siderolabs/talosctl`) has no shell | Use an image with a shell or restructure command to avoid shell | 1 | 2026-02-28 | 2026-02-28 |
| Flux envsubst mangles awk `$N` field references in inline scripts | Flux post-build `envsubst` treats `$N` as variable references even inside YAML strings/single-quoted awk | Escape all awk field refs as `$$N` in Flux-managed YAML (e.g., `$$2`, `$$8`) | 2 | 2026-02-28 | 2026-02-28 |
| `spec.interval: Required value` on HelmRelease dry-run after moving defaults from Flux patches to Kyverno mutating policy | Kyverno admission webhooks fire AFTER server-side apply dry-run validation; CRD-required fields must be present in the manifest before dry-run | Keep required fields (spec.interval) in Flux kustomization patches or set them explicitly in each HelmRelease; Kyverno +(anchor) mutation cannot inject CRD-required fields | 1 | 2026-03-09 | 2026-03-09 |

## False Positives

Things that look like failures but aren't — avoid flagging these.

| Signal | Why It's Not a Problem | Count | Last Seen | Added |
|--------|----------------------|-------|-----------|-------|
| Kustomization firemerge not ready during reconciliation wave | Dependency chain, resolves within 5 min — wait for full cluster reconciliation | 6 | 2026-03-03 | 2026-02-24 |
| traefik-ingress shows DependencyNotReady briefly during reconciliation wave | Normal dependency ordering, resolves within seconds | 5 | 2026-03-09 | 2026-02-25 |
| Multiple kustomizations show "dependency authentik is not ready" during reconciliation | authentik dependency chain, resolves within ~90s — not a failure | 8 | 2026-03-09 | 2026-02-25 |
| authentik 2026.2.0 logs `AttributeError("'Version' object has no attribute '__dict__'")` on startup | Upstream bug, warning-level only, does not affect functionality — API returns 200 | 1 | 2026-02-25 | 2026-02-25 |
| authentik default OAuth Mapping uses deprecated `ak_groups` — emits deprecation warning on outpost proxy requests | Not a failure — requests succeed with HTTP 200. Migrate to `User.groups` in admin UI | 1 | 2026-02-25 | 2026-02-25 |
| vmagent scrape failures for Grafana during k8s-stack upgrade | Pod IP changes during rollover cause transient scrape timeouts/connection refused — resolves once new pod is ready | 1 | 2026-02-25 | 2026-02-25 |
| openclaw startup probe fails with "connection refused" for ~20s after pod start | App takes ~20s to bind port 18789 — startup probe catches this normally, pod becomes ready within 30s | 4 | 2026-03-09 | 2026-02-25 |
| n8n readiness probe "connection refused" for ~20s after pod start during rolling update | n8n takes ~20s to bind port 5678 after container start — transient, resolves once app initializes | 2 | 2026-03-03 | 2026-03-03 |
| n8n `DB_POSTGRESDB_SSL_CA_FILE` whitespace warning on startup | Pre-existing config issue, does not affect DB connectivity | 2 | 2026-03-03 | 2026-03-03 |
| n8n `N8N_RUNNERS_ENABLED` deprecation warning | Env var no longer needed in newer versions — cosmetic, not functional | 2 | 2026-03-03 | 2026-03-03 |
