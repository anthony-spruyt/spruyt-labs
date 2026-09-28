# LiteLLM Proxy - LLM and MCP Gateway

## Overview

Single gateway for every LLM call and most MCP traffic in the cluster: Claude agent pods, Coder workspaces, n8n and dev containers all point `ANTHROPIC_BASE_URL` at it. It exposes Anthropic-compatible (`/v1/messages`) and OpenAI-compatible (`/v1/chat/completions`) APIs plus an MCP gateway at `/mcp`. `litellm-valkey` is its dedicated cache and router-state store; `litellm/app/plugins/` holds
proxy-side Python callbacks.

## Prerequisites

- Authentik OAuth provider, secret and rotation wiring — see [authentik README](../authentik-system/authentik/README.md#oauth-credential-rotation).
- Provider API keys in `litellm/app/litellm-secrets.sops.yaml`, referenced from `config.yaml` as `os.environ/<NAME>`. Anthropic models set no `api_key`; they are subscription passthrough (below).
- `HF_TOKEN` in the same secret, for the llm-guard model download.

## Operations

### Virtual keys and subscription passthrough

Anthropic models use subscription (OAuth) passthrough (`forward_client_headers_to_llm_api: true`): the client's `Authorization` header goes to Anthropic unchanged, so the LiteLLM virtual key must travel in the `x-litellm-api-key` header instead. Never put the virtual key in `ANTHROPIC_AUTH_TOKEN` or `ANTHROPIC_API_KEY` — Anthropic rejects it.

Create one virtual key per consumer in the admin UI (`https://litellm.${EXTERNAL_DOMAIN}`) with its own budget and rate limits. Keys live in Postgres.

| Consumer          | Secret Location                                            | Secret Key    | Injected As                                                 |
| ----------------- | ---------------------------------------------------------- | ------------- | ----------------------------------------------------------- |
| Claude agent pods | `litellm-credentials` in each `claude-agents-*` namespace  | `virtual-key` | `LITELLM_API_KEY`, referenced by `ANTHROPIC_CUSTOM_HEADERS` |
| Coder workspaces  | `coder-workspace-env-*` SOPS secrets in `coder-workspaces` | —             | `LITELLM_API_KEY` and `ANTHROPIC_CUSTOM_HEADERS`            |
| Dev containers    | `~/.secrets/.env.*` (see `DEVELOPMENT.md`)                 | —             | `LITELLM_API_KEY` and `ANTHROPIC_CUSTOM_HEADERS`            |

Agent pods get `LITELLM_API_KEY`, `ANTHROPIC_CUSTOM_HEADERS` and `ANTHROPIC_BASE_URL` injected by `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml`, not by their own manifests. `ANTHROPIC_CUSTOM_HEADERS` uses `$(LITELLM_API_KEY)`, so it must stay listed after it, and the policy writes it as `\\$(LITELLM_API_KEY)` so Kyverno doesn't try to substitute it. The subscription login is
set per credential in n8n (`claudeCodeK8s*` credentials, "Claude OAuth Credentials" field).

### SSO

Built-in OIDC SSO (not an Authentik outpost), from `authentik-system/authentik/app/blueprints/litellm-sso.yaml`. The blueprint's `litellm_role` scope mapping returns `proxy_admin` for members of `LiteLLM Admins` and `internal_user` for everyone else in `LiteLLM Users`; LiteLLM reads it through `GENERIC_USER_ROLE_ATTRIBUTE`. Change admin access by changing group membership in the blueprint, not in
the LiteLLM UI.

### Model management

Models are declared in `config.yaml`, embedded in `litellm/app/values.yaml` under `configMaps.litellm-config`. Edit that file and let Flux reconcile — do not use the Admin API (`POST /model/new`) or the UI, since those writes are lost on the next pod roll.

`store_model_in_db: true` is set, but `supported_db_objects` is scoped to `mcp`, so the DB persists **MCP objects only**. `config.yaml` is authoritative for models. Widening `supported_db_objects` would make DB-stored models shadow the declared ones — don't, without revisiting this.

Adding a Claude model takes two edits in `values.yaml`:

| Key                                 | Entry                                  | Why                                              |
| ----------------------------------- | -------------------------------------- | ------------------------------------------------ |
| `model_list`                        | `anthropic/<model>` pointing at itself | Registers the deployment                         |
| `router_settings.model_group_alias` | `<model>` → `anthropic/<model>`        | Lets clients send the bare name Claude Code uses |

Claude groups deliberately have no `router_settings.fallbacks` — a 429 surfaces to the client instead of silently switching provider.

Omit cost params for models LiteLLM already prices in its bundled `model_prices_and_context_window.json` (all current Claude models). Only set `input_cost_per_token` / `output_cost_per_token` for models absent from that registry, such as OpenRouter entries.

Only live models are registered. Retired names are deliberately left unmapped so they fail fast with a clear error rather than silently routing somewhere unintended.

### MCP servers

MCP servers are registered through the LiteLLM UI and persisted in Postgres (the one DB object type allowed above), not in `config.yaml`. On a rebuild they must be re-added by hand; see [unifi-network-mcp](../unifi-mcp/unifi-network-mcp/README.md#litellm-registration-is-manual) for the reasoning. For each in-cluster MCP server, LiteLLM needs an egress CNP in `litellm/app/network-policies.yaml` and
the server needs an ingress CNP from the `litellm` namespace. `.mcp.json` in the repo root holds a single `litellm` entry; every downstream server is fanned out through it.

### Proxy-side plugins

`litellm/app/plugins/` is mounted into the pod as ConfigMap subPath files under `/app/custom_callbacks/`, with an init container creating the package directories. `middleware/pipeline_plugin.py` is the single callback registered in `config.yaml`; it runs the middlewares listed in `middleware/registry.py`. `DEFAULT_MIDDLEWARE_SPECS` is currently empty, so the `hindsight` and `chatgpt` middlewares
are inert even though their files are still mounted. To enable one, add a `MiddlewareSpec` for it; order matters (Hindsight before ChatGPT, because Hindsight injects into Anthropic `system` and ChatGPT then translates the final system content).

When adding a file to a plugin, also add it to the plugin's ConfigMap generator and its `advancedMounts` list in `values.yaml`. Run the plugin unit tests with `task test:litellm-middleware`.

### Guardrails

`pii-protection` (Presidio sidecars), `prompt-injection` (llm-guard sidecar) and `jev-compaction` (TypeSafe, external) are all `default_on: false`: a caller must opt in per request or per key. `jev-compaction` sends tool output to an external service, so keep it opt-in.

llm-guard runs with `HF_HUB_OFFLINE=1` and loads its model from the `llm-guard-hf-cache` PVC. This is fail-closed on purpose: if that PVC is ever lost or empty, the pod can never become ready. Recovery is to remove `HF_HUB_OFFLINE` from `values.yaml`, let one pod download the model, then restore it (Ref #2592).

### Known issues

| Issue                | Description                                                                                                                     | Mitigation                                                               |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| Lossy passthrough    | `openai/` models on `/v1/messages` are translated via the Responses API — `cache_control` is dropped and `thinking` is remapped | Call `openai/` models on `/v1/chat/completions` when those fields matter |
| Claude Code cost_usd | Broken — internal price table only knows Claude models                                                                          | Use LiteLLM Grafana dashboard for cost tracking                          |
| OTLP metrics         | The OTEL integration derives its metrics URL from the traces endpoint and POSTs metrics to VictoriaTraces, which returns 400    | OTLP metrics stay disabled; metrics come from the `prometheus` callback  |

### Security: PyPI supply chain

LiteLLM PyPI versions 1.82.7-1.82.8 were compromised via a trivy scan dependency. The incident is contained, and Docker/GHCR images were never affected. Retained as standing policy: install from GHCR only, never PyPI, and always pin to a version tag with digest.

### Flux timeout

`litellm/ks.yaml` uses a 30m timeout with a 5m retry interval because `traefik-ingress` depends on it and a slow image pull would otherwise fail the Kustomization after Helm succeeded. Keep the two in step with the HelmRelease timeout (Ref #2591).

## Troubleshooting

1. **SSO redirect loop**

   - **Cause**: `PROXY_BASE_URL` does not match the IngressRoute hostname exactly, or the Authentik redirect URI lacks `/sso/callback`.
   - **Fix**: Align `PROXY_BASE_URL` in `values.yaml` with the blueprint's `redirect_uris`.

2. **Upstream provider 401/403**

   - **Cause**: The alias resolved, but the provider key is missing or invalid. `openrouter/*` and `openai/*` entries name their env var inline (`OPENROUTER_API_KEY`, `OPENAI_API_KEY`).
   - **Fix**: Confirm the relevant key exists in `litellm-secrets` and check the provider's quota. A `BadRequestError` about "no healthy deployments" is different: the model is not registered at all.

3. **Anthropic rejects the request as unauthenticated**

   - **Cause**: The client put the virtual key in `ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN`, so it was forwarded to Anthropic.
   - **Fix**: Send it as `x-litellm-api-key: Bearer <key>` via `ANTHROPIC_CUSTOM_HEADERS`.

4. **llm-guard pod never becomes ready after storage loss**

   - **Cause**: `HF_HUB_OFFLINE=1` against an empty cache PVC.
   - **Fix**: See Guardrails above.

## References

- [LiteLLM Documentation](https://docs.litellm.ai/)
- [LiteLLM Anthropic Provider](https://docs.litellm.ai/docs/providers/anthropic)
- [LiteLLM Routing and Fallbacks](https://docs.litellm.ai/docs/routing)
- [Claude Code LLM Gateway Docs](https://code.claude.com/docs/en/llm-gateway)
- [PyPI Compromise Advisory](https://github.com/BerriAI/litellm/issues/24518)
