# LiteLLM Proxy - Centralized LLM Gateway

## Overview

LiteLLM Proxy provides a centralized LLM gateway exposing both Anthropic-compatible (`/v1/messages`) and OpenAI-compatible (`/v1/chat/completions`) APIs. Claude models route to Anthropic directly, with OpenRouter as the failover provider. Replaces direct Anthropic API usage for Claude Code CLI automation, providing virtual key management, spend tracking, and OTEL observability.

Priority tier: `standard`.

## Prerequisites

- authentik (SSO via OIDC Blueprint)
- cnpg-operator (CloudNativePG)
- external-secrets (cross-namespace OIDC credential sync)
- plugin-barman-cloud (CNPG backup plugin)
- litellm-valkey (Redis-compatible cache and router state)
- rook-ceph-cluster-storage (PVCs for the ChatGPT plugin auth data and the llm-guard model cache)

## Operations

### Virtual Key Management

Generate virtual keys after deployment via the LiteLLM admin UI (`https://litellm.<EXTERNAL_DOMAIN>`) or API:

```bash
curl -X POST "http://litellm.litellm.svc.cluster.local:4000/key/generate" \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "key_alias": "n8n-automation",
    "max_budget": 100,
    "tpm_limit": 1000000,
    "rpm_limit": 120
  }'
```

Virtual keys are stored in PostgreSQL. Each consumer should have a dedicated key with appropriate budget and rate limits.

| Consumer          | Secret Location                                           | Secret Key    | Injected As            |
| ----------------- | --------------------------------------------------------- | ------------- | ---------------------- |
| Claude agent pods | `litellm-credentials` in each `claude-agents-*` namespace | `virtual-key` | `ANTHROPIC_AUTH_TOKEN` |
| Coder workspaces  | Per-developer workspace secret or `.env`                  | —             | `ANTHROPIC_AUTH_TOKEN` |

Agent pods get `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_BASE_URL` injected by the Kyverno policy in `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml` — not by their own manifests.

### Authentik SSO

LiteLLM uses built-in OIDC SSO (not Authentik outpost). The OIDC provider and application are deployed declaratively via Authentik Blueprint (`blueprints/litellm-sso.yaml`). Credentials are synced cross-namespace via ExternalSecret (same pattern as Coder, Grafana, Vaultwarden).

Blueprint creates:

- Groups: `LiteLLM Users` (parent), `LiteLLM Admins` (child)
- Provider: OAuth2/OIDC, confidential client
- Application: slug `litellm`, redirect URI `/sso/callback`
- Policy binding: restricts access to `LiteLLM Users` group members

### Model Management

Models are declared in `config.yaml`, embedded in `litellm/app/values.yaml` under `configMaps.litellm-config`. Edit that file and let Flux reconcile — do not use the Admin API (`POST /model/new`) or the UI, since those writes are lost on the next pod roll.

`store_model_in_db: true` is set, but `supported_db_objects` is scoped to `mcp`, so the DB persists **MCP objects only**. `config.yaml` is authoritative for models. Widening `supported_db_objects` would make DB-stored models shadow the declared ones — don't, without revisiting this.

Adding a Claude model takes three edits in `values.yaml`:

| Key                                 | Entry                                                    | Why                                               |
| ----------------------------------- | -------------------------------------------------------- | ------------------------------------------------- |
| `model_list`                        | `anthropic/<model>` pointing at itself                   | Registers the deployment                          |
| `router_settings.model_group_alias` | `<model>` → `anthropic/<model>`                          | Lets clients send the bare name Claude Code uses  |
| `router_settings.fallbacks`         | Both the bare and `anthropic/`-prefixed key → OpenRouter | Router sees the group pre- and post-alias-resolve |

Omit cost params for models LiteLLM already prices in its bundled `model_prices_and_context_window.json` (all current Claude models). Only set `input_cost_per_token` / `output_cost_per_token` for models absent from that registry, such as OpenRouter entries.

Only live models are registered. Retired names (e.g. `claude-opus-4-8`) are deliberately left unmapped so they fail fast with a clear error rather than silently routing somewhere unintended.

### Known Issues

| Issue                | Description                                                                                                                     | Mitigation                                                               |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| Lossy passthrough    | `openai/` models on `/v1/messages` are translated via the Responses API — `cache_control` is dropped and `thinking` is remapped | Call `openai/` models on `/v1/chat/completions` when those fields matter |
| Claude Code cost_usd | Broken — internal price table only knows Claude models                                                                          | Use LiteLLM Grafana dashboard for cost tracking                          |

### Security: PyPI Supply Chain Advisory

LiteLLM PyPI versions 1.82.7-1.82.8 were compromised via a trivy scan dependency. The incident is contained, and Docker/GHCR images were never affected. Retained as standing policy: install from GHCR only, never PyPI, and always pin to a version tag with digest.

## Troubleshooting

1. **LiteLLM fails to start — database connection error**

   - **Symptom**: Pod CrashLoopBackOff, logs show "connection refused" to PostgreSQL
   - **Resolution**: Verify CNPG cluster is healthy: `kubectl get cluster -n litellm`. The CNPG cluster must be `Ready` before LiteLLM starts. Check that `litellm-cnpg-cluster-app` secret exists.

2. **SSO redirect loop**

   - **Symptom**: Login redirects endlessly between LiteLLM and Authentik
   - **Resolution**: Verify `PROXY_BASE_URL` matches the IngressRoute hostname exactly. Check Authentik Application redirect URI includes `/sso/callback`.

3. **Upstream provider 401/403**

   - **Symptom**: The alias resolves, but the upstream call returns 401 or 403
   - **Resolution**: The provider key is missing or invalid. `openrouter/*` and `openai/*` entries name their env var inline (`OPENROUTER_API_KEY`, `OPENAI_API_KEY`); the `anthropic/*` entries set no `api_key` and rely on `ANTHROPIC_API_KEY` from `litellm-secrets`. Confirm the relevant key exists and check the provider's quota.
   - **Note**: A 401 means the alias resolved and only the credential is at fault — contrast with a `BadRequestError` about "no healthy deployments", which means the model is not registered at all.

## References

- [LiteLLM Documentation](https://docs.litellm.ai/)
- [LiteLLM Anthropic Provider](https://docs.litellm.ai/docs/providers/anthropic)
- [LiteLLM Routing and Fallbacks](https://docs.litellm.ai/docs/routing)
- [Claude Code LLM Gateway Docs](https://code.claude.com/docs/en/llm-gateway)
- [PyPI Compromise Advisory](https://github.com/BerriAI/litellm/issues/24518)
