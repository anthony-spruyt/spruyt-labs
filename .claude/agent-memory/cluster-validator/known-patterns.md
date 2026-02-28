# Known Patterns

## Operational Patterns

Timing, behavioral, and environmental knowledge learned from validation runs.

| Pattern | Context | Count | Last Seen | Added |
|---------|---------|-------|-----------|-------|
| firemerge dependency chain (firefly-iii → firemerge → traefik-ingress) takes 3-5 min to fully reconcile | Full cluster reconciliation wait | 5 | 2026-02-28 | 2026-02-24 |
| flux-operator upgrade triggers FluxInstance re-reconciliation (~3s) and OutdatedVersion event for flux | Normal behavior after operator upgrade | 2 | 2026-02-28 | 2026-02-25 |
| authentik dependency chain (authentik → many apps → traefik-ingress) settles within ~90s | Full cluster reconciliation wait after flux-system changes | 2 | 2026-02-25 | 2026-02-25 |

## Failure Signatures

Error patterns and their known resolutions.

| Error Pattern | Root Cause | Resolution | Count | Last Seen | Added |
|---------------|------------|------------|-------|-----------|-------|
| `exec: "/bin/sh": stat /bin/sh: no such file or directory` in CronJob pod | Scratch-based container image (e.g., `ghcr.io/siderolabs/talosctl`) has no shell | Use an image with a shell or restructure command to avoid shell | 1 | 2026-02-28 | 2026-02-28 |
| Flux envsubst mangles awk `$N` field references in inline scripts | Flux post-build `envsubst` treats `$N` as variable references even inside YAML strings/single-quoted awk | Escape all awk field refs as `$$N` in Flux-managed YAML (e.g., `$$2`, `$$8`) | 1 | 2026-02-28 | 2026-02-28 |

## False Positives

Things that look like failures but aren't — avoid flagging these.

| Signal | Why It's Not a Problem | Count | Last Seen | Added |
|--------|----------------------|-------|-----------|-------|
| Kustomization firemerge not ready during reconciliation wave | Dependency chain, resolves within 5 min — wait for full cluster reconciliation | 5 | 2026-02-28 | 2026-02-24 |
| traefik-ingress shows DependencyNotReady briefly during reconciliation wave | Normal dependency ordering, resolves within seconds | 3 | 2026-02-28 | 2026-02-25 |
| Multiple kustomizations show "dependency authentik is not ready" during reconciliation | authentik dependency chain, resolves within ~90s — not a failure | 3 | 2026-02-28 | 2026-02-25 |
| authentik 2026.2.0 logs `AttributeError("'Version' object has no attribute '__dict__'")` on startup | Upstream bug, warning-level only, does not affect functionality — API returns 200 | 1 | 2026-02-25 | 2026-02-25 |
| authentik default OAuth Mapping uses deprecated `ak_groups` — emits deprecation warning on outpost proxy requests | Not a failure — requests succeed with HTTP 200. Migrate to `User.groups` in admin UI | 1 | 2026-02-25 | 2026-02-25 |
| vmagent scrape failures for Grafana during k8s-stack upgrade | Pod IP changes during rollover cause transient scrape timeouts/connection refused — resolves once new pod is ready | 1 | 2026-02-25 | 2026-02-25 |
| openclaw startup probe fails with "connection refused" for ~20s after pod start | App takes ~20s to bind port 18789 — startup probe catches this normally, pod becomes ready within 30s | 2 | 2026-02-28 | 2026-02-25 |
