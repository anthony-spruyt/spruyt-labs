# Claude Agents

Ephemeral Claude Code agent pods spawned by n8n. Five namespaces, two tiers.

## Namespace Matrix

| Namespace                         | GitHub           | kubectl   | MCP Servers                          | Priority | RBAC                    |
| --------------------------------- | ---------------- | --------- | ------------------------------------ | -------- | ----------------------- |
| `claude-agents-read`              | read + comment   | none      | agentplatform, bravesearch, context7 | low      | SA only                 |
| `claude-agents-write`             | write (push, PR) | none      | agentplatform, bravesearch, context7 | standard | SA only                 |
| `claude-agents-spruyt-labs-read`  | read + comment   | read-only | + victoriametrics                    | low      | `claude-agent-reader`   |
| `claude-agents-spruyt-labs-sre`   | read + comment   | operator  | + victoriametrics                    | high     | `claude-agent-operator` |
| `claude-agents-spruyt-labs-write` | write (push, PR) | operator  | + victoriametrics                    | standard | `claude-agent-operator` |

**Generic** namespaces have no kube-apiserver access. **Infra** (`spruyt-labs-*`) namespaces get kube-apiserver egress CNPs, RBAC ClusterRoleBindings, and additional MCP servers.

## RBAC

| ClusterRole             | Capabilities                                                                      |
| ----------------------- | --------------------------------------------------------------------------------- |
| `claude-agent-reader`   | get/list/watch on all standard resources, secrets list only (no values)           |
| `claude-agent-operator` | reader + pod delete/eviction, deployment/statefulset/daemonset patch, scale patch |

## Shared Base (`claude-agents-shared/base/`)

All namespaces inherit:

| Resource                         | Purpose                                                                                   |
| -------------------------------- | ----------------------------------------------------------------------------------------- |
| `rbac.yaml`                      | `claude-agent` ServiceAccount                                                             |
| `rbac-spawner.yaml`              | Role/RoleBinding for n8n pod creation                                                     |
| `network-policies.yaml`          | CNPs: world egress, OTLP (vmsingle, vlogs, vtraces), Brave Search MCP, agent-platform MCP |
| `github-secret-store.yaml`       | ESO SecretStore → `github-system`                                                         |
| `github-bot-gitconfig-read.yaml` | Read-only git identity                                                                    |
| `github-rotation-rbac.yaml`      | Token rotation CronJob RBAC                                                               |
| `mcp-credentials.sops.yaml`      | Encrypted MCP API keys                                                                    |

Per-namespace overlays add: MCP config, settings profiles, GitHub ExternalSecret, and optionally network policies, RBAC, SSH key, and write gitconfig.

## Kyverno Injection

`inject-claude-agent-config` ClusterPolicy mutates all pods with `managed-by: n8n-claude-code`:

| Rule                      | Namespaces  | Injects                                                                                    |
| ------------------------- | ----------- | ------------------------------------------------------------------------------------------ |
| `strip-explicit-priority` | all 5       | Removes n8n-set priority (Kyverno sets correct one)                                        |
| `inject-priority-*`       | per-tier    | `low-priority` (read), `standard` (write), `high-priority` (sre)                           |
| `inject-shared-config`    | all 5       | gh CLI config, gitconfig, settings profiles, managed-settings, Context7 key, OTEL env vars |
| `inject-managed-mcp`      | all 5       | MCP config volume + agent-platform auth token                                              |
| `inject-github-ssh`       | write tiers | SSH key + write gitconfig (with commit signing)                                            |
| `inject-repo-clone-write` | write tiers | SSH clone init container + pre-commit install                                              |
| `inject-repo-clone-read`  | read + sre  | HTTPS clone init container (token-authenticated)                                           |

Clone preconditions enforce URL prefix: `git@github.com:anthony-spruyt/` (write) or `https://github.com/anthony-spruyt/` (read/sre).

## MCP Servers

| Server          | URL                                          | Auth                                | CNP Location                   |
| --------------- | -------------------------------------------- | ----------------------------------- | ------------------------------ |
| agentplatform   | `n8n-webhook.n8n-system.svc:8080`            | Bearer token from `mcp-credentials` | shared base                    |
| bravesearch     | `brave-search-mcp.brave-search-mcp.svc:8000` | none                                | shared base                    |
| context7        | `mcp.context7.com` (external)                | API key from `mcp-credentials`      | world egress (shared base)     |
| victoriametrics | `mcp-victoriametrics.observability.svc:8080` | none                                | per-namespace (spruyt-labs-\*) |

`$${}` syntax in MCP config is replaced at runtime from pod env vars.

### Adding a New MCP Server

1. Add entry to relevant `claude-mcp-config.yaml`
1. If authenticated: add key to `mcp-credentials.sops.yaml`, add env var injection to Kyverno policy
1. If in-cluster: add egress CNP (shared base for all namespaces, per-namespace overlay for tier-specific)
1. If in-cluster: add ingress CNP on destination allowing agent namespace(s)

## Settings Profiles

Mounted at `/etc/claude/settings/` via Kyverno. Set in n8n: `--settings /etc/claude/settings/<profile>.json`

| Namespace                         | Profiles                                     |
| --------------------------------- | -------------------------------------------- |
| `claude-agents-read`              | `renovate-triage`, `review-pr`, `validate`   |
| `claude-agents-write`             | `execute-issue`, `pr-fix`, `renovate-fix`    |
| `claude-agents-spruyt-labs-read`  | `renovate-triage`, `review-pr`, `validate`   |
| `claude-agents-spruyt-labs-sre`   | `sre-health-check`, `sre-triage`, `validate` |
| `claude-agents-spruyt-labs-write` | `execute-issue`, `pr-fix`, `renovate-fix`    |

## Credential Rotation

| Secret         | Method                                                                          |
| -------------- | ------------------------------------------------------------------------------- |
| GitHub tokens  | `github-token-rotation` CronJob (automatic)                                     |
| GitHub SSH key | Same CronJob (write namespaces only)                                            |
| MCP API keys   | Manual: `sops cluster/apps/claude-agents-shared/base/mcp-credentials.sops.yaml` |

## Prerequisites

- Flux CD, External Secrets Operator
- `github-token-rotation` CronJob in `github-system`
- Kyverno `inject-claude-agent-config` ClusterPolicy
- PriorityClasses: `low-priority`, `standard`, `high-priority`

## Troubleshooting

| Symptom               | Check                                                                               |
| --------------------- | ----------------------------------------------------------------------------------- |
| GitHub 401            | `kubectl get externalsecret -n <ns>` — trigger manual rotation if stale             |
| ESO sync error        | `kubectl describe secretstore github-secret-store -n <ns>`                          |
| Pod creation denied   | `kubectl get rolebinding -n <ns>` — verify spawner RBAC                             |
| Egress blocked        | `kubectl get ciliumnetworkpolicy -n <ns>`                                           |
| kubectl forbidden     | `kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<ns>:claude-agent` |
| MCP connection failed | Verify egress CNP exists + ingress CNP on destination includes namespace            |
