# Claude Agents

## Overview

n8n spawns short-lived Claude Code agent pods in five namespaces (label `managed-by: n8n-claude-code`). Almost everything these pods run with is injected at admission time by Kyverno, not by the namespace manifests. This README covers what each namespace gets, where the injection happens, and which places must change together.

`base/` holds the shared resources (spawner RBAC, egress CNPs, GitHub SecretStore, read-only gitconfig, MCP credentials, plugin bootstrap script). Each `claude-agents-*/claude-agents/app/` overlay adds its MCP config, settings profiles, GitHub and LiteLLM credentials, and any tier-specific CNPs and RBAC.

## Namespace Tiers

| Namespace                         | GitHub token    | Clone | kube-apiserver | Priority (Kyverno) |
| --------------------------------- | --------------- | ----- | -------------- | ------------------ |
| `claude-agents-read`              | read            | HTTPS | none           | `low-priority`     |
| `claude-agents-write`             | write + SSH key | SSH   | none           | `standard`         |
| `claude-agents-spruyt-labs-read`  | read            | HTTPS | reader         | `low-priority`     |
| `claude-agents-spruyt-labs-sre`   | read            | HTTPS | operator       | `high-priority`    |
| `claude-agents-spruyt-labs-write` | write + SSH key | SSH   | operator       | `standard`         |

Generic namespaces have no kube-apiserver egress or RBAC. `spruyt-labs-*` namespaces add an `allow-kube-api-egress` CNP and a ClusterRoleBinding for the `claude-agent` ServiceAccount:

- `claude-agent-reader` (defined in `claude-agents-spruyt-labs-read`): get/list/watch on core, apps, batch, Flux, Cilium, Ceph, CNPG and other CRDs used for diagnosis. No access to Secrets at all.
- `claude-agent-operator` (defined in `claude-agents-spruyt-labs-sre`, also bound by `spruyt-labs-write`): reader plus pod delete, pod eviction, and patch on deployments/statefulsets/daemonsets and their `scale` subresources.

The ClusterRoles live in the namespace that first needed them, so pruning `claude-agents-spruyt-labs-sre` would also remove the role that `spruyt-labs-write` binds.

## Kyverno Injection

`cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml` mutates every pod with `managed-by: n8n-claude-code` in the five namespaces. The namespace list is repeated in each rule.

| Rule                                  | Namespaces  | Injects                                                                                                                                                                                                                        |
| ------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `strip-explicit-priority`             | all         | Removes any priority set by n8n                                                                                                                                                                                                |
| `inject-priority-{low,standard,high}` | per tier    | `priorityClassName` from the table above                                                                                                                                                                                       |
| `inject-shared-config`                | all         | gh CLI config (with a `gh-config-sync` sidecar that re-copies the rotated token every 30s), read-only gitconfig, settings profiles, managed settings, plugin-bootstrap init container, OTEL env vars, LiteLLM base URL and key |
| `inject-managed-mcp`                  | all         | `claude-mcp-config` at `/etc/mcp/mcp.json` and `/etc/claude-code/managed-mcp.json`, plus `AGENT_PLATFORM_MCP_AUTH_TOKEN`                                                                                                       |
| `inject-github-ssh`                   | write tiers | SSH key and the write gitconfig (commit signing)                                                                                                                                                                               |
| `inject-repo-clone-write`             | write tiers | SSH clone init container, pre-commit install, project plugin bootstrap                                                                                                                                                         |
| `inject-repo-clone-read`              | read + sre  | HTTPS clone with the read token, project plugin bootstrap                                                                                                                                                                      |
| `validate-clone-url-write` / `-read`  | per tier    | Rejects a `CLONE_URL` that is not `git@github.com:anthony-spruyt/...` (write) or `https://github.com/anthony-spruyt/...` (read/sre)                                                                                            |

Three further policies act on the same label: `set-agent-deadline` sets `activeDeadlineSeconds` from the `agent-timeout` pod annotation (default 3h), `validate-agent-deadline` rejects pods without one, and `cleanup-agent-pods` deletes Succeeded/Failed pods hourly as a backstop for n8n's own cleanup.

## MCP Servers

Each overlay's `claude-mcp-config.yaml` defines two servers:

| Server          | Endpoint                                     | Auth                                                                         |
| --------------- | -------------------------------------------- | ---------------------------------------------------------------------------- |
| `agentplatform` | `n8n-webhook.n8n-system.svc:8080/mcp/...`    | `AGENT_PLATFORM_MCP_AUTH_TOKEN` from `mcp-credentials`, plus job/session IDs |
| `litellm`       | `litellm.litellm.svc.cluster.local:4000/mcp` | LiteLLM virtual key from `litellm-credentials`                               |

Every other MCP server (e.g. Brave Search, VictoriaMetrics, n8n-mcp, UniFi) is reached through the LiteLLM MCP gateway and registered in LiteLLM, not here. Port 8080 on `n8n-webhook` is the [`mcp-header-proxy`](https://github.com/anthony-spruyt/mcp-header-proxy) sidecar added by a postRenderer in `n8n-system/n8n/app/release.yaml`.

`$${VAR}` in the MCP config is Flux's escape for a literal `${VAR}`; Claude Code expands it from the pod environment at runtime.

### Adding an MCP server

- **Preferred:** register it in LiteLLM (see `litellm/README.md`); no agent-side change is needed.
- **Direct:** add it to every relevant `claude-mcp-config.yaml`; if it needs a credential, add the key to `base/mcp-credentials.sops.yaml` and inject it in `inject-managed-mcp`; if it is in-cluster, add an egress CNP here (base for all tiers, overlay for one) and an ingress CNP on the destination listing the agent namespaces.

## Credential Rotation

| Credential                                   | Rotation                                                                                                                |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| GitHub App tokens (`github-bot-credentials`) | `github-token-rotation` CronJob in `github-system`, every 30 min; force-syncs the ExternalSecret in all five namespaces |
| Bot SSH key (`github-bot-ssh-key`)           | `bot-ssh-key-rotation` CronJob, daily; force-syncs the ExternalSecret in both write-tier namespaces                     |
| `mcp-credentials`                            | Manual: `sops cluster/apps/claude-agents-shared/base/mcp-credentials.sops.yaml`                                         |
| `litellm-credentials`                        | Manual: one LiteLLM virtual key per namespace in each overlay's `litellm-credentials.sops.yaml`                         |

The Claude subscription login is not stored here; it is set per n8n credential (see `litellm/README.md`).

## Adding an Agent Namespace

The namespace name is hardcoded outside this directory. All of these must change together:

1. A new overlay under `cluster/apps/claude-agents-<name>/` including `../../../claude-agents-shared/base`
2. Every rule in `kyverno/policies/app/inject-claude-agent-config.yaml` that applies to the tier
3. `litellm/litellm/app/network-policies.yaml` (`allow-claude-agents-ingress`)
4. `n8n-system/n8n/app/network-policies.yaml` (`allow-claude-agent-ingress`, for the agentplatform MCP)
5. `observability/victoria-traces-single/app/network-policies.yaml` (OTLP traces)
6. `nexus-system/nexus/app/network-policies.yaml`, write tiers only (pre-commit package pulls)
7. `github-system/github-token-rotation/app/`: a `reader-role-binding-<ns>.yaml` and the namespace loop in `cronjob.yaml`
8. For write tiers, `FORCE_SYNC_NAMESPACES` in `github-system/bot-ssh-key-rotation/app/cronjob.yaml`
9. A matching Claude Code K8s credential and Dispatcher branch in n8n

## Troubleshooting

1. **Pod rejected with "CLONE_URL in write namespaces must use SSH format" (or the HTTPS variant)**

   - **Cause**: n8n dispatched a role to the wrong tier. The Dispatcher picks SSH for `renovate-fix`, `execute-issue` and `revert` and HTTPS for everything else.
   - **Fix**: Route the role to a namespace of the matching tier in the n8n Dispatcher.

2. **Pod rejected with "Agent pods must have activeDeadlineSeconds set"**

   - **Cause**: `set-agent-deadline` did not mutate the pod (Kyverno webhook timeout or policy not ready), so the validate policy blocks it.
   - **Fix**: Check `set-agent-deadline` is Ready and the Kyverno admission controller is healthy.

3. **gh CLI returns 401 mid-run**

   - **Cause**: Installation tokens last 1h. The pod mounts the rotated token through the `gh-config-sync` sidecar; if `github-token-rotation` stopped running, every pod ends up with an expired token.
   - **Fix**: Check the last `github-token-rotation` Job in `github-system`.

4. **MCP connection refused or times out**

   - **Cause**: Needs both an egress CNP from the agent namespace and an ingress CNP on the destination that lists that namespace.
   - **Fix**: See "Adding an Agent Namespace" for the destinations that hardcode the namespace list.
