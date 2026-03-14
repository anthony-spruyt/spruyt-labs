# Known Patterns

## Operational Patterns

Timing, behavioral, and environmental knowledge learned from validation runs.

| Pattern | Context | Count | Last Seen | Added |
|---------|---------|-------|-----------|-------|
| firemerge dependency chain (firefly-iii → firemerge → traefik-ingress) takes 3-5 min to fully reconcile | Full cluster reconciliation wait | 7 | 2026-03-13 | 2026-02-24 |
| flux-operator upgrade triggers FluxInstance re-reconciliation (~3s) and OutdatedVersion event for flux | Normal behavior after operator upgrade | 4 | 2026-03-13 | 2026-02-25 |
| authentik dependency chain (authentik → many apps → traefik-ingress) settles within ~90s | Full cluster reconciliation wait after flux-system changes | 8 | 2026-03-13 | 2026-02-25 |
| CronJob validation requires manual test job -- last completed job ran previous version | CronJob workload type detection | 3 | 2026-03-13 | 2026-02-28 |
| YAML comment-only changes (e.g., schema directives) reconcile instantly with no resource drift | Kustomize strips comments, producing identical output | 1 | 2026-03-01 | 2026-03-01 |
| n8n queue-mode deployment (main + worker + webhook) all roll simultaneously on image bump | HelmRelease values.yaml image tag change triggers rolling update of all 3 deployments | 3 | 2026-03-13 | 2026-03-03 |
| Large image first-pull (~1GB) can exceed 10m HelmRelease timeout; Flux auto-rollback then retries successfully with cached image | openclaw image update, image pulled in 10m1s exceeding timeout, auto-retry succeeded | 1 | 2026-03-09 | 2026-03-09 |
| Revert of failed kyverno policy change recovers full cluster within ~90s; Flux cleans up removed ClusterPolicy resources automatically | Revert commit after kyverno-policies reconciliation failure | 1 | 2026-03-09 | 2026-03-09 |
| Kyverno policy matching CRDs (e.g., HelmRelease) requires full GVK path `group/version/Kind` in `kinds` field; bare Kind name only works for core/built-in resources | Kyverno webhook registration, CRD matching | 1 | 2026-03-10 | 2026-03-10 |
| Kyverno `--crdWatcher=false` prevents webhook auto-registration of CRD-based resources; policy is accepted but webhook never routes CRD admission requests to Kyverno | Kyverno config, CRD policy, webhook rules | 3 | 2026-03-10 | 2026-03-10 |
| Kyverno chart v3.7.1 `config.crdWatcher` maps to ConfigMap, NOT container args; correct path is `admissionController.crdWatcher: true` | Helm values path mismatch, silent no-op | 1 | 2026-03-10 | 2026-03-10 |
| Helm silently ignores unknown/misplaced values keys -- always verify rendered manifest with `helm get manifest` | Helm chart values validation | 1 | 2026-03-10 | 2026-03-10 |
| Kyverno 1.17.x on K8s 1.35: webhooks not auto-updated for CRD-targeted policies due to v1alpha1.MutatingAdmissionPolicy reflector failures (upstream kyverno/kyverno#15362) | Kyverno webhook, CRD policy, K8s API version mismatch | 1 | 2026-03-10 | 2026-03-10 |
| Kyverno downgrade (3.7.1->3.6.1 / v1.17->v1.16) succeeds cleanly; crdWatcher works in v1.16.1 on K8s 1.35; webhook auto-registers CRD resources within seconds of policy creation | Kyverno version workaround, crdWatcher validation | 1 | 2026-03-10 | 2026-03-10 |
| Kyverno minor chart upgrade (3.6.1->3.6.3 / v1.16.1->v1.16.3) reconciles within ~3 min; migration job runs and completes; downstream deps (kyverno-policies, descheduler, qdrant) settle immediately after | Kyverno patch upgrade, helm-release type | 1 | 2026-03-10 | 2026-03-10 |
| Kyverno mutate policy with `+(anchor)` only fires on CREATE/UPDATE; existing resources need forced reconciliation to receive mutations | Kyverno admission-only mutation, no background | 1 | 2026-03-10 | 2026-03-10 |
| Talos extraManifests CRD updates via SSA: bundle-version annotations on existing CRDs may not update due to field ownership conflict between `talos` manager and previous manager; CRD schemas are updated correctly | Talos config, CRD update, SSA field ownership | 1 | 2026-03-10 | 2026-03-10 |
| Middleware base template with Flux envsubst deploys to all consuming namespaces simultaneously; verify substitution in multiple namespaces | lan-ip-whitelist shared middleware, kustomize base pattern | 1 | 2026-03-12 | 2026-03-12 |
| SSE endpoints return HTTP 200 but curl hangs (timeout) because connection is long-lived; use short --max-time and check headers for `text/event-stream` | MCP VM SSE endpoint validation | 1 | 2026-03-12 | 2026-03-12 |
| ConfigMap hash change (configMapGenerator) triggers pod rollout even when HelmRelease version unchanged; verify new pod logs after values.yaml env var changes | mcp-victoriametrics SSE-to-HTTP mode switch, configMapGenerator hash | 1 | 2026-03-13 | 2026-03-13 |
| flux-operator overrides flux-system namespace labels; labels declared in cluster/apps/flux-system/namespace.yaml are not applied because flux-operator manages the namespace with `app.kubernetes.io/managed-by: flux-operator`; use kustomize patch in flux-instance values.yaml instead | flux-system namespace, descheduler label exclusion | 2 | 2026-03-13 | 2026-03-13 |

## Failure Signatures

Error patterns and their known resolutions.

| Error Pattern | Root Cause | Resolution | Count | Last Seen | Added |
|---------------|------------|------------|-------|-----------|-------|
| `exec: "/bin/sh": stat /bin/sh: no such file or directory` in CronJob pod | Scratch-based container image (e.g., `ghcr.io/siderolabs/talosctl`) has no shell | Use an image with a shell or restructure command to avoid shell | 1 | 2026-02-28 | 2026-02-28 |
| Flux envsubst mangles awk `$N` field references in inline scripts | Flux post-build `envsubst` treats `$N` as variable references even inside YAML strings/single-quoted awk | Escape all awk field refs as `$$N` in Flux-managed YAML (e.g., `$$2`, `$$8`) | 2 | 2026-02-28 | 2026-02-28 |
| `spec.interval: Required value` on HelmRelease dry-run after moving defaults from Flux patches to Kyverno mutating policy | Kyverno admission webhooks fire AFTER server-side apply dry-run validation; CRD-required fields must be present in the manifest before dry-run | Keep required fields (spec.interval) in Flux kustomization patches or set them explicitly in each HelmRelease; Kyverno +(anchor) mutation cannot inject CRD-required fields | 3 | 2026-03-12 | 2026-03-09 |
| OOMKilled (exit code 137) on mcp-victoriametrics with 128Mi-1Gi limits | Container memory limit too low for application startup; process killed within 7s after single log line | Increase memory limit aggressively (2Gi worked); mcp-victoriametrics v1.18.0 in SSE mode needs >1Gi at startup | 4 | 2026-03-12 | 2026-03-12 |
| HelmRelease stuck in `pending-upgrade` with no successful revision history | All revisions failed (install + upgrades), Flux error: `missing target release for rollback: cannot remediate failed release` | Manual `helm rollback <release> <revision> -n <ns>` to unstick, then Flux retries with new values | 1 | 2026-03-12 | 2026-03-12 |

## False Positives

Things that look like failures but aren't — avoid flagging these.

| Signal | Why It's Not a Problem | Count | Last Seen | Added |
|--------|----------------------|-------|-----------|-------|
| Kustomization firemerge not ready during reconciliation wave | Dependency chain, resolves within 5 min — wait for full cluster reconciliation | 7 | 2026-03-13 | 2026-02-24 |
| traefik-ingress shows DependencyNotReady briefly during reconciliation wave | Normal dependency ordering, resolves within seconds | 8 | 2026-03-13 | 2026-02-25 |
| Multiple kustomizations show "dependency authentik is not ready" during reconciliation | authentik dependency chain, resolves within ~90s — not a failure | 9 | 2026-03-13 | 2026-02-25 |
| authentik 2026.2.0 logs `AttributeError("'Version' object has no attribute '__dict__'")` on startup | Upstream bug, warning-level only, does not affect functionality — API returns 200 | 1 | 2026-02-25 | 2026-02-25 |
| authentik default OAuth Mapping uses deprecated `ak_groups` — emits deprecation warning on outpost proxy requests | Not a failure — requests succeed with HTTP 200. Migrate to `User.groups` in admin UI | 1 | 2026-02-25 | 2026-02-25 |
| vmagent scrape failures for Grafana during k8s-stack upgrade | Pod IP changes during rollover cause transient scrape timeouts/connection refused — resolves once new pod is ready | 1 | 2026-02-25 | 2026-02-25 |
| openclaw startup probe fails with "connection refused" for ~20s after pod start | App takes ~20s to bind port 18789 — startup probe catches this normally, pod becomes ready within 30s | 8 | 2026-03-14 | 2026-02-25 |
| n8n readiness probe "connection refused" for ~20s after pod start during rolling update | n8n takes ~20s to bind port 5678 after container start — transient, resolves once app initializes | 3 | 2026-03-13 | 2026-03-03 |
| n8n `DB_POSTGRESDB_SSL_CA_FILE` whitespace warning on startup | Pre-existing config issue, does not affect DB connectivity | 3 | 2026-03-13 | 2026-03-03 |
| n8n `N8N_RUNNERS_ENABLED` deprecation warning | Env var no longer needed in newer versions — cosmetic, not functional | 3 | 2026-03-13 | 2026-03-03 |
| cloudflared connIndex=3 `control stream encountered a failure while serving` during startup | Transient QUIC reconnect on 4th tunnel connection — self-resolves within seconds, other 3 connections healthy | 1 | 2026-03-13 | 2026-03-13 |
| openclaw `/ready` returns HTTP 503 for ~5 min after startup due to health-monitor grace periods (startup-grace: 60s, channel-connect-grace: 120s) | App health-monitor waits for Discord channel connection before reporting ready; switching readiness probe to `/healthz` avoids this issue entirely | 3 | 2026-03-14 | 2026-03-13 |
| headlamp HelmRelease stalled on old revision with `Helm rollback to previous release` message | Pre-existing failure unrelated to current changes; headlamp chart upgrade failed and Flux rolled back; blocks traefik-ingress dependency | 1 | 2026-03-14 | 2026-03-14 |
