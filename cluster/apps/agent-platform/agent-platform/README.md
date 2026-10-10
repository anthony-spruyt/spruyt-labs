# agent-platform - Temporal + .NET agent orchestration

## Overview

Cluster side of the `anthony-spruyt/agent-platform` service, which replaces the n8n agent workflows (#3467). One image runs as two Deployments in `agent-platform`: `web` (Intake webhooks + AgentGateway MCP) and `worker` (Temporal workflows and activities). The worker starts short-lived Claude Code pods in `agent-platform-agents`. This directory holds the namespaces, RBAC, network policies and
Kyverno guardrails; the Deployments, Services and VPA arrive with the spike (step 3 of #3467).

The pod spec for agents (env, MCP config, settings, clone, deadline) is built in code by the worker, not injected by Kyverno. None of the n8n-era agent policies (`managed-by: n8n-claude-code`) apply to these pods.

## Namespaces

| Namespace               | Holds                                                          | Pod labels                                                             |
| ----------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `agent-platform`        | `web` and `worker` Deployments, worker credentials             | `app.kubernetes.io/name: agent-platform-web` / `agent-platform-worker` |
| `agent-platform-agents` | Agent pods and agent-only secrets; PSA `restricted` (enforced) | `managed-by: agent-platform` (required by Kyverno)                     |

`agent-platform-agents` is excluded from the descheduler: evicting an agent pod kills its run.

## Ports

| Pod   | Port   | Purpose                   | Reached from                                        |
| ----- | ------ | ------------------------- | --------------------------------------------------- |
| `web` | `8080` | Intake (webhooks, health) | Traefik; only webhook paths will be routed publicly |
| `web` | `8081` | AgentGateway `/mcp`       | Agent pods only; never routed through Traefik       |

The agent MCP config points at `http://agent-platform-web.agent-platform.svc.cluster.local:8081/mcp`, assuming the spike names the Service `agent-platform-web`. Keep the two ports on separate Service ports so a Traefik route can never expose `/mcp`.

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
| worker              | LiteLLM `4000`                                               | `litellm/litellm` `allow-agent-platform-ingress`                                                                                                     |
| worker              | world `443` (GitHub, Discord)                                | n/a                                                                                                                                                  |
| web, worker, agents | vmsingle `8428`, VictoriaLogs `9428`, VictoriaTraces `10428` | VictoriaTraces: `observability/victoria-traces-single` `allow-agent-platform-traces-ingress`; vmsingle and VictoriaLogs accept any in-cluster source |
| agents              | AgentGateway `8081`                                          | `allow-web-agent-gateway-ingress` (this app)                                                                                                         |
| agents              | LiteLLM `4000`                                               | `litellm/litellm` `allow-agent-platform-ingress`                                                                                                     |
| agents              | world `443` (GitHub)                                         | n/a                                                                                                                                                  |
| agents              | Nexus `8081` (npm/PyPI/NuGet)                                | `nexus-system/nexus` `nexus-default`                                                                                                                 |
| Traefik             | web `8080`                                                   | `allow-web-traefik-ingress` (this app)                                                                                                               |

Policies in `agent-platform-agents` select every pod in the namespace, and agent pods accept no ingress. vmagent scrape rules and the run-data database (step 4) are added when those exist.

## Kyverno Guardrails

Both live in `agents/kyverno-policies.yaml`:

- `validate-agent-platform-pods` (ValidatingPolicy, `Deny`, on CREATE): every pod in `agent-platform-agents` must carry `managed-by: agent-platform`, and must set `activeDeadlineSeconds` between 1 and 3600. The per-run GitHub installation token expires after 1h, and the worker derives the deadline from its `expires_at`.
- `cleanup-agent-platform-pods` (DeletingPolicy): every 15 minutes, deletes agent pods older than 2h in any phase, as a backstop for the worker's own delete.

## Owner-only Secrets

Create these before the spike. Nothing references them yet; the spike adds them to the `kustomization.yaml` files and the pod specs. Create each with `sops <file>` as a `v1` `Secret` using `stringData`:

| File                                                                            | Secret               | Namespace               | Keys                                             | Used by                                                    |
| ------------------------------------------------------------------------------- | -------------------- | ----------------------- | ------------------------------------------------ | ---------------------------------------------------------- |
| `cluster/apps/agent-platform/agent-platform/agents/agent-credentials.sops.yaml` | `agent-credentials`  | `agent-platform-agents` | `claude-code-oauth-token`, `litellm-virtual-key` | Agent pods (`CLAUDE_CODE_OAUTH_TOKEN`, LiteLLM key header) |
| `cluster/apps/agent-platform/agent-platform/app/worker-credentials.sops.yaml`   | `worker-credentials` | `agent-platform`        | `litellm-virtual-key`                            | Worker (Jev and other LiteLLM calls)                       |

- `claude-code-oauth-token`: a long-lived subscription token from `claude setup-token`. A token separate from the Coder workspace's can be revoked on its own; usage still counts against the same subscription.
- `litellm-virtual-key`: one LiteLLM virtual key per consumer (agents, worker), so spend and rate limits are tracked separately.

Rotation is the same `sops <file>` edit; agent pods pick up the new value on their next run, the worker on restart.

## References

- [#3467](https://github.com/anthony-spruyt/spruyt-labs/issues/3467) - migration plan and step order
- [Kyverno ValidatingPolicy](https://kyverno.io/docs/policy-types/validating-policy/)
- [Kyverno DeletingPolicy](https://kyverno.io/docs/policy-types/deleting-policy/)
