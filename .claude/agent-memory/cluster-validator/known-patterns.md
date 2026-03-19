# Known Patterns

## Operational Patterns

Timing, behavioral, and environmental knowledge learned from validation runs.

| Pattern | Context | Count | Last Seen | Added |
|---------|---------|-------|-----------|-------|
| firemerge dependency chain (firefly-iii → firemerge → traefik-ingress) takes 3-5 min to fully reconcile | Full cluster reconciliation wait | 10 | 2026-03-19 | 2026-02-24 |
| flux-operator upgrade triggers FluxInstance re-reconciliation (~3s) and OutdatedVersion event for flux | Normal behavior after operator upgrade | 5 | 2026-03-18 | 2026-02-25 |
| authentik dependency chain (authentik → many apps → traefik-ingress) settles within ~90s | Full cluster reconciliation wait after flux-system changes | 8 | 2026-03-13 | 2026-02-25 |
| CronJob validation requires manual test job -- last completed job ran previous version | CronJob workload type detection | 3 | 2026-03-13 | 2026-02-28 |
| YAML comment-only changes (e.g., schema directives, resource-sizing comments) reconcile instantly with no resource drift | Kustomize strips comments, producing identical output | 2 | 2026-03-17 | 2026-03-01 |
| n8n queue-mode deployment (main + worker + webhook) all roll simultaneously on image bump | HelmRelease values.yaml image tag change triggers rolling update of all 3 deployments | 4 | 2026-03-18 | 2026-03-03 |
| Large image first-pull (~1GB) can exceed 10m HelmRelease timeout; Flux auto-rollback then retries successfully with cached image | openclaw image update, image pulled in 10m1s exceeding timeout, auto-retry succeeded | 3 | 2026-03-16 | 2026-03-09 |
| Revert of failed kyverno policy change recovers full cluster within ~90s; Flux cleans up removed ClusterPolicy resources automatically | Revert commit after kyverno-policies reconciliation failure | 1 | 2026-03-09 | 2026-03-09 |
| Kyverno policy matching CRDs (e.g., HelmRelease) requires full GVK path `group/version/Kind` in `kinds` field; bare Kind name only works for core/built-in resources | Kyverno webhook registration, CRD matching | 1 | 2026-03-10 | 2026-03-10 |
| Kyverno `--crdWatcher=false` prevents webhook auto-registration of CRD-based resources; policy is accepted but webhook never routes CRD admission requests to Kyverno | Kyverno config, CRD policy, webhook rules | 3 | 2026-03-10 | 2026-03-10 |
| Kyverno chart v3.7.1 `config.crdWatcher` maps to ConfigMap, NOT container args; correct path is `admissionController.crdWatcher: true` | Helm values path mismatch, silent no-op | 1 | 2026-03-10 | 2026-03-10 |
| Helm silently ignores unknown/misplaced values keys -- always verify rendered manifest with `helm get manifest` | Helm chart values validation | 2 | 2026-03-17 | 2026-03-10 |
| Kyverno 1.17.x on K8s 1.35: webhooks not auto-updated for CRD-targeted policies due to v1alpha1.MutatingAdmissionPolicy reflector failures (upstream kyverno/kyverno#15362) | Kyverno webhook, CRD policy, K8s API version mismatch | 1 | 2026-03-10 | 2026-03-10 |
| Kyverno downgrade (3.7.1->3.6.1 / v1.17->v1.16) succeeds cleanly; crdWatcher works in v1.16.1 on K8s 1.35; webhook auto-registers CRD resources within seconds of policy creation | Kyverno version workaround, crdWatcher validation | 1 | 2026-03-10 | 2026-03-10 |
| Kyverno minor chart upgrade (3.6.1->3.6.3 / v1.16.1->v1.16.3) reconciles within ~3 min; migration job runs and completes; downstream deps (kyverno-policies, descheduler, qdrant) settle immediately after | Kyverno patch upgrade, helm-release type | 1 | 2026-03-10 | 2026-03-10 |
| Kyverno mutate policy with `+(anchor)` only fires on CREATE/UPDATE; existing resources need forced reconciliation to receive mutations | Kyverno admission-only mutation, no background | 1 | 2026-03-10 | 2026-03-10 |
| Talos extraManifests CRD updates via SSA: bundle-version annotations on existing CRDs may not update due to field ownership conflict between `talos` manager and previous manager; CRD schemas are updated correctly | Talos config, CRD update, SSA field ownership | 1 | 2026-03-10 | 2026-03-10 |
| Middleware base template with Flux envsubst deploys to all consuming namespaces simultaneously; verify substitution in multiple namespaces | lan-ip-whitelist shared middleware, kustomize base pattern | 1 | 2026-03-12 | 2026-03-12 |
| SSE endpoints return HTTP 200 but curl hangs (timeout) because connection is long-lived; use short --max-time and check headers for `text/event-stream` | MCP VM SSE endpoint validation | 1 | 2026-03-12 | 2026-03-12 |
| OCIRepository secretRef addition reconciles instantly with no downstream impact; source controller re-authenticates on next poll cycle without triggering pod rollouts | Flux OCI source auth config change, ghcr-docker-config secret | 1 | 2026-03-16 | 2026-03-16 |
| cowboysysop VPA chart installs CRDs via a pre-install Job (`vertical-pod-autoscaler-crds`) using `bitnamilegacy/kubectl` image; CRD creation takes ~13s; all 3 VPA pods start after CRDs are ready | VPA initial deployment, helm-release type | 1 | 2026-03-17 | 2026-03-17 |
| Large-scale VPA rollout (50 files, 86 objects) reconciles within ~5 min across all namespaces; VPA objects with `updateMode: Off` show recommendations within minutes of creation; newly created VPAs may show empty status initially | VPA workload rollout, kustomization type | 2 | 2026-03-19 | 2026-03-18 |
| cert-manager minor version upgrade (v1.19.4->v1.20.0) rolls all 3 deployments (controller, cainjector, webhook) in ~29s; webhook regenerates TLS certs; ACME registrations re-verified; all 27 certificates remain Ready | cert-manager helm-release minor upgrade | 1 | 2026-03-18 | 2026-03-18 |
| Spegel chart (spegel@0.6.0) silently accepts `verticalPodAutoscaler` values but does NOT template VPA resources; a standalone VPA manifest is needed for VPA monitoring of Spegel | Helm chart values no-op, VPA integration | 1 | 2026-03-17 | 2026-03-17 |
| ConfigMap hash change (configMapGenerator) triggers pod rollout even when HelmRelease version unchanged; verify new pod logs after values.yaml env var changes | mcp-victoriametrics SSE-to-HTTP mode switch, configMapGenerator hash; openclaw gateway auth/config changes; openclaw init-skills script changes; openclaw env var additions; openclaw JSON config changes; openclaw subagent spawn permissions; openclaw exec approval + channel config; openclaw heartbeat disable | 13 | 2026-03-17 | 2026-03-13 |
| flux-operator overrides flux-system namespace labels; labels declared in cluster/apps/flux-system/namespace.yaml are not applied because flux-operator manages the namespace with `app.kubernetes.io/managed-by: flux-operator`; use kustomize patch in flux-instance values.yaml instead | flux-system namespace, descheduler label exclusion | 2 | 2026-03-13 | 2026-03-13 |

## Failure Signatures

Error patterns and their known resolutions.

| Error Pattern | Root Cause | Resolution | Count | Last Seen | Added |
|---------------|------------|------------|-------|-----------|-------|
| `exec: "/bin/sh": stat /bin/sh: no such file or directory` in CronJob pod | Scratch-based container image (e.g., `ghcr.io/siderolabs/talosctl`) has no shell | Use an image with a shell or restructure command to avoid shell | 1 | 2026-02-28 | 2026-02-28 |
| Flux envsubst mangles awk `$N` field references in inline scripts | Flux post-build `envsubst` treats `$N` as variable references even inside YAML strings/single-quoted awk | Escape all awk field refs as `$$N` in Flux-managed YAML (e.g., `$$2`, `$$8`) | 2 | 2026-02-28 | 2026-02-28 |
| Flux postBuild envsubst replaces `${VAR}` in ALL string fields including JSON config values; use `$${VAR}` to produce literal `${VAR}` for runtime env-var resolution by apps | openclaw.json env-var refs for hooks.token and gateway.token were being substituted to empty strings by Flux | 1 | 2026-03-15 | 2026-03-15 |
| `spec.interval: Required value` on HelmRelease dry-run after moving defaults from Flux patches to Kyverno mutating policy | Kyverno admission webhooks fire AFTER server-side apply dry-run validation; CRD-required fields must be present in the manifest before dry-run | Keep required fields (spec.interval) in Flux kustomization patches or set them explicitly in each HelmRelease; Kyverno +(anchor) mutation cannot inject CRD-required fields | 3 | 2026-03-12 | 2026-03-09 |
| OOMKilled (exit code 137) on mcp-victoriametrics with 128Mi-1Gi limits | Container memory limit too low for application startup; process killed within 7s after single log line | Increase memory limit aggressively (2Gi worked); mcp-victoriametrics v1.18.0 in SSE mode needs >1Gi at startup | 4 | 2026-03-12 | 2026-03-12 |
| HelmRelease stuck in `pending-upgrade` with no successful revision history | All revisions failed (install + upgrades), Flux error: `missing target release for rollback: cannot remediate failed release` | Manual `helm rollback <release> <revision> -n <ns>` to unstick, then Flux retries with new values | 1 | 2026-03-12 | 2026-03-12 |
| `Startup probe failed: HTTP probe failed with statuscode: 404` on FastMCP-based apps | FastMCP streamable-http transport serves only `/mcp` endpoint; no `/health` path exists | Switch probes from `httpGet` to `tcpSocket` on the app port | 1 | 2026-03-15 | 2026-03-15 |
| Traefik chart v39.0.5 `experimental.localPlugins` requires `type` field (`hostPath`, `inlinePlugin`, or `localPath`); bare `moduleName` alone causes template error | Chart template `_helpers.tpl` `getLocalPluginType` enforces type selection | Add `type: localPath` with `volumeName` and `mountPath`; chart auto-creates volumeMount | 1 | 2026-03-15 | 2026-03-15 |
| Renovate container image bump to non-existent tag causes ImagePullBackOff; old pod already terminated by rolling update leaving service DOWN | Renovate auto-merge before image published to GHCR | Revert commit; retry with correct tag once available | 3 | 2026-03-16 | 2026-03-16 |
| Revert commit can be superseded by a newer commit pushed before Flux finishes reconciling the revert; Flux picks up the latest revision, skipping the intermediate revert | Fast-follow commit after revert, Flux git source polling | Verify the final deployed revision matches the actual HEAD, not the revert commit | 1 | 2026-03-16 | 2026-03-16 |
| Missing `targetNamespace` in ks.yaml causes "namespace not specified" error for namespace-scoped resources (e.g., VPA); Flux applies the resource without a namespace and the API server rejects the patch | csi-addons-controller-manager ks.yaml missing targetNamespace | Add `targetNamespace: <namespace>` to ks.yaml spec; fix reconciles within seconds | 2 | 2026-03-18 | 2026-03-18 |

## False Positives

Things that look like failures but aren't — avoid flagging these.

| Signal | Why It's Not a Problem | Count | Last Seen | Added |
|--------|----------------------|-------|-----------|-------|
| Kustomization firemerge not ready during reconciliation wave | Dependency chain, resolves within 5 min — wait for full cluster reconciliation | 8 | 2026-03-19 | 2026-02-24 |
| traefik-ingress shows DependencyNotReady briefly during reconciliation wave | Normal dependency ordering, resolves within seconds | 23 | 2026-03-19 | 2026-02-25 |
| Multiple kustomizations show "dependency authentik is not ready" during reconciliation | authentik dependency chain, resolves within ~90s — not a failure | 12 | 2026-03-18 | 2026-02-25 |
| mcp-victoriametrics shows "dependency victoria-metrics-k8s-stack is not ready" during reconciliation wave | Dependency chain, resolves within 2 min — parent KS already Ready but child hasn't re-evaluated yet | 1 | 2026-03-19 | 2026-03-19 |
| authentik 2026.2.0 logs `AttributeError("'Version' object has no attribute '__dict__'")` on startup | Upstream bug, warning-level only, does not affect functionality — API returns 200 | 1 | 2026-02-25 | 2026-02-25 |
| authentik default OAuth Mapping uses deprecated `ak_groups` — emits deprecation warning on outpost proxy requests | Not a failure — requests succeed with HTTP 200. Migrate to `User.groups` in admin UI | 1 | 2026-02-25 | 2026-02-25 |
| vmagent scrape failures for Grafana during k8s-stack upgrade | Pod IP changes during rollover cause transient scrape timeouts/connection refused — resolves once new pod is ready | 1 | 2026-02-25 | 2026-02-25 |
| openclaw startup probe fails with "connection refused" for ~20s after pod start | App takes ~20s to bind port 18789 — startup probe catches this normally, pod becomes ready within 30s | 22 | 2026-03-17 | 2026-02-25 |
| openclaw gateway token auth: `token_missing` and `pairing required` WS rejections after switching to token mode | Expected behavior — clients must complete token pairing via Control UI; not a failure | 1 | 2026-03-14 | 2026-03-14 |
| openclaw `Proxy headers detected from untrusted address` when trustedProxies doesn't include Traefik pod CIDR | Gateway ignores X-Forwarded-For from non-trusted IPs; functional but loses real client IP detection | 1 | 2026-03-14 | 2026-03-14 |
| n8n readiness probe "connection refused" for ~20s after pod start during rolling update | n8n takes ~20s to bind port 5678 after container start — transient, resolves once app initializes | 4 | 2026-03-18 | 2026-03-03 |
| n8n `DB_POSTGRESDB_SSL_CA_FILE` whitespace warning on startup | Pre-existing config issue, does not affect DB connectivity | 4 | 2026-03-18 | 2026-03-03 |
| n8n `N8N_RUNNERS_ENABLED` deprecation warning | Env var no longer needed in newer versions — cosmetic, not functional | 4 | 2026-03-18 | 2026-03-03 |
| cloudflared connIndex=3 `control stream encountered a failure while serving` during startup | Transient QUIC reconnect on 4th tunnel connection — self-resolves within seconds, other 3 connections healthy | 1 | 2026-03-13 | 2026-03-13 |
| openclaw `/ready` returns HTTP 503 for ~5 min after startup due to health-monitor grace periods (startup-grace: 60s, channel-connect-grace: 120s) | App health-monitor waits for Discord channel connection before reporting ready; switching readiness probe to `/healthz` avoids this issue entirely | 3 | 2026-03-14 | 2026-03-13 |
| headlamp v0.40.1 session-ttl crash workaround: `sessionTTL: null` in values.yaml suppresses `-session-ttl` flag that causes crash on startup (upstream kubernetes-sigs/headlamp#4883) | HelmRelease upgrade after rollback, helm-release type | 1 | 2026-03-14 | 2026-03-14 |
| FastMCP 3.0.2 streamable-http transport has no `/health` endpoint; only `/mcp` responds (406 without MCP headers); use `tcpSocket` probes instead of `httpGet` | kubectl-mcp-server probe config, FastMCP health check | 1 | 2026-03-15 | 2026-03-15 |
| Traefik chart 39.x installs Gateway API CRDs by default; on clusters with `safe-upgrades.gateway.networking.k8s.io` VAP, set `install.crds: Skip` and `upgrade.crds: Skip` in HelmRelease | Traefik HR CRD management, Gateway API VAP conflict | 1 | 2026-03-15 | 2026-03-15 |
| MCP detection tools (certs_detect_tool, cilium_detect_tool etc.) previously failed with Forbidden due to missing apiextensions.k8s.io CRD read access; resolved by adding CRD read rule to ClusterRole (commit c157a8cc, issue #696) | kubectl-mcp-server RBAC, MCP tool detection | 2 | 2026-03-18 | 2026-03-18 |
| `check_crd_exists` MCP tool may return false negatives for CRDs that exist; verify with `kubectl get crd <name>` as fallback | VPA CRD existed but check_crd_exists returned false | 1 | 2026-03-18 | 2026-03-18 |
| OpenClaw hooks feature requires OPENCLAW_HOOKS_TOKEN in openclaw-secrets.sops.yaml; config uses env-var substitution and gateway refuses to start if hooks.enabled=true with empty token | openclaw hooks config, missing secret key | 2 | 2026-03-15 | 2026-03-15 |
| SOPS secret change for alertmanager config triggers config reload without pod restart; verify via "Loading configuration file" / "Completed loading" log lines | VMAlertmanager config reload, SOPS secret update | 1 | 2026-03-15 | 2026-03-15 |
| Alertmanager webhook DNS failure (`no such host`) produces cascading self-referential alerts (AlertmanagerFailedToSendAlerts, AlertmanagerClusterFailedToSendAlerts) that resolve automatically once the config is corrected | Alertmanager webhook misconfiguration, openclaw service name | 1 | 2026-03-15 | 2026-03-15 |
| cert-manager controller logs "owning resource not found in cache" for completed Orders/CertificateRequests on startup | Benign cache population during controller restart; references historical completed resources | 1 | 2026-03-18 | 2026-03-18 |
