# agent-platform - Temporal + .NET agent orchestration

## Overview

Cluster side of the `anthony-spruyt/agent-platform` service, which replaces the n8n agent workflows (#3467). One image runs as two Deployments in `agent-platform`: `web` (Intake webhooks + AgentGateway MCP) and `worker` (Temporal workflows and activities). The worker starts short-lived Claude Code pods in `agent-platform-agents`. This directory holds the namespaces, RBAC, network policies, Kyverno
guardrails, the two HelmReleases (bjw-s app-template) and their VPAs.

The pod spec for agents (env, MCP config, settings, clone, deadline) is built in code by the worker, not injected by Kyverno. None of the n8n-era agent policies (`managed-by: n8n-claude-code`) apply to these pods.

## Namespaces

| Namespace               | Holds                                                          | Pod labels                                                             |
| ----------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `agent-platform`        | `web` and `worker` Deployments, worker credentials             | `app.kubernetes.io/name: agent-platform-web` / `agent-platform-worker` |
| `agent-platform-agents` | Agent pods and agent-only secrets; PSA `restricted` (enforced) | `managed-by: agent-platform` (required by Kyverno)                     |

`agent-platform-agents` is excluded from the descheduler: evicting an agent pod kills its run.

## Releases

`web` and `worker` are two HelmReleases (`agent-platform-web`, `agent-platform-worker`) so `app.kubernetes.io/name` equals the release name, which the CiliumNetworkPolicy selectors match on. They share one image pin; Renovate bumps both through the `# renovate:` annotation above each `tag`. Each has its own folder and Flux Kustomization (`agent-platform-web`, `agent-platform-worker`); chart-level
settings are in `web/app/values.yaml` and `worker/app/values.yaml`. The worker depends on the web Kustomization for the `agent-platform-session` Secret, and on `temporal` for the run-data role, Role and CA copy.

Only the worker mounts a ServiceAccount token. Both releases read `AgentGateway__SessionTokenKey` from the `agent-platform-session` Secret. Both use the Temporal namespace `agent-platform`.

The worker pod runs a `migrate` initContainer (same image, `AgentPlatform__Role: Migrate`) that applies the run-data EF Core migrations before the worker starts; the web pod has no database access.

## Ports

| Pod   | Port   | Purpose                   | Reached from                                        |
| ----- | ------ | ------------------------- | --------------------------------------------------- |
| `web` | `8080` | Intake (webhooks, health) | Traefik; only `/webhooks/github` is routed publicly |
| `web` | `8081` | AgentGateway `/mcp`       | Agent pods only; never routed through Traefik       |

The Service `agent-platform-web` exposes `webhooks` (`8080`) and `mcp` (`8081`). The agent MCP config points at `http://agent-platform-web.agent-platform.svc.cluster.local:8081/mcp`. Keep the two ports on separate Service ports so a Traefik route can never expose `/mcp`. The public host `hooks.${EXTERNAL_DOMAIN}` goes through the Cloudflare tunnel to Traefik (`ingress/agent-platform/`), which
routes only the exact path `/webhooks/github` to port `8080`, with no SSO: Intake verifies the GitHub HMAC signature itself.

## RBAC

| ServiceAccount          | Namespace               | Access                                                                                               |
| ----------------------- | ----------------------- | ---------------------------------------------------------------------------------------------------- |
| `agent-platform-worker` | `agent-platform`        | The worker manages agent pods and per-run Secrets in `agent-platform-agents`.                        |
| `agent-platform-web`    | `agent-platform`        | None; no token mounted                                                                               |
| `agent-runner`          | `agent-platform-agents` | None; no token mounted. SRE agents that need cluster read access get a separate ServiceAccount later |

The worker creates the per-run GitHub token Secret after the pod, with an ownerReference to the pod so it is garbage-collected with it. Leave `blockOwnerDeletion` unset on that ownerReference: setting it needs `update` on `pods/finalizers`, which is outside the worker's Role.

## Network Policies

DNS is allowed cluster-wide by `allow-kube-dns-egress`. Everything else is allowlisted, on both sides where the destination has an ingress policy:

| From                | To                                                           | Destination-side policy                                                                                                                              |
| ------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| worker              | kube-apiserver `6443`                                        | n/a                                                                                                                                                  |
| web, worker         | Temporal frontend `7233`                                     | `temporal-system/temporal` `allow-temporal-frontend-clients-ingress`                                                                                 |
| worker              | Temporal CNPG cluster `5432` (run-data database)             | `temporal-system/temporal` `allow-temporal-cnpg-agent-platform-ingress`                                                                              |
| worker              | LiteLLM `4000`                                               | `litellm/litellm` `allow-agent-platform-ingress`                                                                                                     |
| worker              | llm-tool-guard `8080` (text scans)                           | `litellm/litellm` `llm-tool-guard-policy`                                                                                                            |
| worker              | world `443` (GitHub, Discord)                                | n/a                                                                                                                                                  |
| web, worker, agents | vmsingle `8428`, VictoriaLogs `9428`, VictoriaTraces `10428` | VictoriaTraces: `observability/victoria-traces-single` `allow-agent-platform-traces-ingress`; vmsingle and VictoriaLogs accept any in-cluster source |
| agents              | AgentGateway `8081`                                          | `allow-web-agent-gateway-ingress` (this app)                                                                                                         |
| agents              | LiteLLM `4000`                                               | `litellm/litellm` `allow-agent-platform-ingress`                                                                                                     |
| agents              | world `443` (GitHub)                                         | n/a                                                                                                                                                  |
| agents              | Nexus `8081` (npm/PyPI/NuGet)                                | `nexus-system/nexus` `nexus-default`                                                                                                                 |
| Traefik             | web `8080`                                                   | `allow-web-traefik-ingress` (this app)                                                                                                               |

Policies in `agent-platform-agents` select every pod in the namespace, and agent pods accept no ingress. Agent pods send telemetry only as `POST` to the OTLP ingest path on each port (Cilium L7 rules in `allow-otel-egress`). vmagent scrape rules are added when those exist.

## Kyverno Guardrails

Both live in `agents/app/kyverno-policies.yaml`:

- `validate-agent-platform-pods` (ValidatingPolicy, `Deny`, on CREATE): every pod in `agent-platform-agents` must carry `managed-by: agent-platform`, and must set `activeDeadlineSeconds` between 1 and 3600. The per-run GitHub installation token expires after 1h, and the worker derives the deadline from its `expires_at`.
- `cleanup-agent-platform-pods` (DeletingPolicy): every 15 minutes, deletes agent pods older than 2h in any phase, as a backstop for the worker's own delete.

## Secrets

| Secret                   | Namespace               | Source                                           | Keys                                                                           | Used by                                                                                                                      |
| ------------------------ | ----------------------- | ------------------------------------------------ | ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| `agent-credentials`      | `agent-platform-agents` | SOPS (`agents/app/agent-credentials.sops.yaml`)  | `claude-code-oauth-token`, `litellm-key-read`, `litellm-key-cluster-read`      | Agent pods, via `secretKeyRef` from the pod spec the worker builds                                                           |
| `worker-credentials`     | `agent-platform`        | SOPS (`worker/app/worker-credentials.sops.yaml`) | `github-app-private-key`, `github-read-app-private-key`, `litellm-virtual-key` | Worker: `GitHub__PrivateKey`, `GitHub__ReadApp__PrivateKey` (read-tier agent tokens), `LiteLlm__ApiKey` (Jev, LiteLLM calls) |
| `agent-platform-session` | `agent-platform`        | External Secrets `Password` generator            | `session-token-key`                                                            | Web and worker, as `AgentGateway__SessionTokenKey`                                                                           |
| `agent-platform-rundata` | `agent-platform`        | External Secrets, copied from `temporal-system`  | `ConnectionStrings__rundata`, `ca.crt`                                         | Worker and its `migrate` initContainer (run-data connection and `ca.crt`)                                                    |

- `claude-code-oauth-token`: a long-lived subscription token from `claude setup-token`. A token separate from the Coder workspace's can be revoked on its own; usage still counts against the same subscription.
- `litellm-key-read` and `litellm-key-cluster-read`: one LiteLLM virtual key per agent tier. `litellm-virtual-key` is the worker's own key, so spend and rate limits are tracked separately.
- `agent-platform-session` is generated once (`CreatedOnce`, `Orphan`, immutable), so a deleted Secret stays deleted. To rotate it, delete both the Secret and the ExternalSecret, let Flux recreate them, then restart web and worker; Reloader does not fire on a recreated Secret.

`agent-platform-rundata` is built by `worker/app/run-data-eso.yaml` from two `temporal-system` secrets: the `agent_platform` role password (`temporal-cnpg-agent-platform`) and a CA copy holding only `ca.crt` (`temporal-cnpg-ca-public`). It refreshes every 5m. The connection string uses `SSL Mode=VerifyFull` and expects the `ca.crt` key mounted at `/etc/agent-platform/rundata-ca/ca.crt`. The
database is `agent_platform` on the Temporal CNPG cluster; see `temporal-system/temporal/README.md`. Agents inspect it read-only through the `agent_platform` source in `db-mcp`.

Rotate the SOPS secrets with `sops <file>`; agent pods pick up the new value on their next run, the worker on restart.

## Alerts

`worker/app/vmrule.yaml` alerts on failed RenovateTriage runs from the Temporal server metrics: `RenovateTriageWorkflowFailed` (a `RenovateTriageWorkflow` run failed or timed out) and `RenovateTriageActivityFailing` (an activity failed or timed out on 5 or more attempts in 15m; retries that later succeed stay below that). The metrics carry `exported_namespace="agent_platform"` and
`workflowType`/`activityType` labels.

It also alerts on two worker OTLP gauges (`service_name="agent-platform-worker"`, exported every 60s): `RenovateTriagePendingStuck` (`triage_pending_total` stayed above 0 for 24h) and `RenovateTriageClaudeCooldownStuck` (`claude_cooldown_active` stayed above 0 for 24h). Each needs more than 1300 samples in the window, so neither fires in the first ~22h after a fresh deploy.

## References

- [#3467](https://github.com/anthony-spruyt/spruyt-labs/issues/3467) - migration plan and step order
- [Kyverno ValidatingPolicy](https://kyverno.io/docs/policy-types/validating-policy/)
- [Kyverno DeletingPolicy](https://kyverno.io/docs/policy-types/deleting-policy/)
