# LiteLLM Proxy - LLM and MCP Gateway

## Overview

Single gateway for every LLM call and most MCP traffic in the cluster: Claude agent pods, Coder workspaces, n8n and dev containers all point `ANTHROPIC_BASE_URL` at it. It exposes Anthropic-compatible (`/v1/messages`) and OpenAI-compatible (`/v1/chat/completions`) APIs plus an MCP gateway at `/mcp`. `litellm-valkey` is its dedicated cache and router-state store. Proxy-side Python middleware comes
from [`anthony-spruyt/litellm-middleware`](https://github.com/anthony-spruyt/litellm-middleware).

## Prerequisites

- Authentik OAuth provider, secret and rotation wiring — see [authentik README](../authentik-system/authentik/README.md#oauth-credential-rotation).
- Provider API keys in `litellm/app/litellm-secrets.sops.yaml`, referenced from `config.yaml` as `os.environ/<NAME>`. Anthropic models set no `api_key`; they are subscription passthrough (below).
- `HF_TOKEN` in the same secret, for the llm-guard model download.
- `TOOL_GUARD_TEAM_IDS` in the same secret: the comma-separated LiteLLM team IDs whose requests the tool-guard middleware enforces.

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

### Database credentials

The `litellm` Postgres login is ESO-generated (`sl_` prefix) into `litellm-cnpg-owner` by `litellm/app/cnpg-roles-eso.yaml`; nothing is in SOPS and superuser access is off. `bootstrap.initdb.secret` points CNPG at it, so CNPG no longer generates `litellm-cnpg-cluster-app`. `DATABASE_URL` interpolates `LITELLM_DB_PASSWORD` (`dependsOn` orders it first).

The database is deliberately not a db-mcp source: it holds virtual keys, stored provider credentials and MCP server tokens. Use `kubectl cnpg psql litellm-cnpg-cluster -n litellm -- -d litellm`.

To rotate, delete both the Secret and the ExternalSecret (`kubectl -n litellm delete secret,externalsecret litellm-cnpg-owner`). Flux recreates the ExternalSecret with a new password and CNPG applies it. Then `kubectl -n litellm rollout restart deploy/litellm` - Reloader ignores a recreated Secret, and agents routed through LiteLLM lose it until the restart.

### Valkey credentials

`litellm-valkey` ACL passwords live in `litellm-valkey-users`, which only ESO writes: `litellm-valkey/app/users-eso.yaml` has one `sl_`-prefixed `CreatedOnce` ExternalSecret per user. Nothing is in SOPS. Valkey has Reloader auto mode, so it restarts when that secret changes; the LiteLLM pods restart too because `REDIS_PASSWORD` reads it.

The `llm-tool-guard` user's password reaches the scanner through `VALKEY_PASSWORD`; its ACL is in `litellm-valkey/app/values.yaml`.

To rotate one user, delete its ExternalSecret (`kubectl -n litellm delete externalsecret litellm-valkey-user-<user>`). Never delete the `litellm-valkey-users` secret itself - every user would get a new password at once.

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

LiteLLM loads the upstream `main` `model_prices_and_context_window.json` at startup over the world HTTPS egress, falling back to the copy bundled in the image. Omit cost params for models that map prices (all current Claude models, including some the pinned image doesn't bundle yet). Only set `input_cost_per_token` / `output_cost_per_token` for models absent from it, such as OpenRouter entries.

Only live models are registered. Retired Opus, Sonnet and Haiku names are not rejected, because some clients can't change the model they send. `model_group_alias` maps the known ones (including the Haiku 4.5 names) to the 5.5 groups, and the `*claude*opus*` / `*claude*sonnet*` / `*claude*haiku*` catch-all deployments send any other name containing those substrings to Opus 5.5 / Sonnet 5.5 / Haiku
5.5. That includes other providers' names such as `openrouter/anthropic/claude-opus-4.1`. LiteLLM tries aliases, then exact `model_name`s, then wildcards, so a newly registered model is never shadowed by a catch-all. Matching is case-sensitive.

### MCP servers

MCP servers are registered through the LiteLLM UI and persisted in Postgres (the one DB object type allowed above), not in `config.yaml`. On a rebuild they must be re-added by hand; see [unifi-network-mcp](../unifi-mcp/unifi-network-mcp/README.md#litellm-registration-is-manual) for the reasoning. For each in-cluster MCP server, LiteLLM needs an egress CNP in `litellm/app/network-policies.yaml` and
the server needs an ingress CNP from the `litellm` namespace. `.mcp.json` in the repo root holds a single `litellm` entry; every downstream server is fanned out through it.

### Proxy middleware

The middleware package ships as the `ghcr.io/anthony-spruyt/litellm-middleware` image, mounted read-only as a Kubernetes `image` volume at `/opt/litellm-middleware`, which is on `PYTHONPATH`. The kubelet pulls it, so the pod needs no egress for it. `litellm_middleware.pipeline_plugin.pipeline_middleware` is the single callback in `config.yaml`. Code, tests, the middleware list and how each
middleware works live in the [middleware repo](https://github.com/anthony-spruyt/litellm-middleware#readme).

- The middleware imports LiteLLM internals that change between releases, so the cluster runs only a LiteLLM the middleware repo's CI has passed. Renovate here doesn't read the registry for the LiteLLM image. The `custom.litellm-middleware-tested` datasource in `renovate-overrides.json5` reads the tag and digest from `litellm-image.yaml` on the middleware repo's `main`. That pin moves only when the
  middleware repo merges a Renovate bump PR, and that PR runs the integration suite against the new LiteLLM. Upgrade by merging the bump there; the matching PR opens here on the next Renovate run. If the new version needs a middleware fix, release that fix first; Renovate groups the LiteLLM and middleware image bumps under `litellm`, so they land in one PR when both are pending.
  `tests/litellm-middleware-contract.bats` checks the callback, mount path and `PYTHONPATH` here against the deployed middleware release. If `litellm-image.yaml` moves or changes shape, the lookup fails and LiteLLM bumps stop (the dashboard shows the lookup failure); they are never untested.
- `tool-guard` sends each new tool result to the `llm-tool-guard` scanner (`TOOL_GUARD_URL`) and wraps those it flags, or could not check, in an `<untrusted-tool-output>` marker with verdict `suspected-prompt-injection` or `unchecked`, which tells the model to treat the text as data. It rewrites only the text, in place in the original request, so fields such as `cache_control` and `is_error` are
  preserved. It applies to the teams listed in `TOOL_GUARD_TEAM_IDS` in `litellm-secrets`; those teams can use only the endpoints the [middleware README](https://github.com/anthony-spruyt/litellm-middleware#tool-guard) lists for enforced keys, and get a client error on any other.
- After a rollout, check the LiteLLM logs for `failed to load <name> middleware` (an optional middleware is missing) or a startup crash (a required one failed to import).

### Rate-limit headers

`ratelimit-headers` restores Anthropic's `anthropic-ratelimit-unified-*` response headers, which LiteLLM renames to `llm_provider-*`, so Claude Code's status line gets `rate_limits`. It is optional: if it fails to import, the proxy serves without it. Remove it once LiteLLM forwards those headers unprefixed or adds a setting to do so.

### Secret masking

`secret-masking` is always on for `/v1/messages`, `/v1/chat/completions`, `/v1/responses`, `/v1/responses/compact`, `/v1/completions` and Gemini `generateContent`/`streamGenerateContent`, and for the body that `count_tokens`/`input_tokens` forward to the provider. Credentials with a known prefix (GitHub, Google, Anthropic, OpenAI, AWS, LiteLLM `sk-`, PEM private keys and others in `_PATTERNS`) are
swapped for a fake with the same prefix, length and character classes before the request leaves the proxy. Fakes in the reply, including streamed text and tool-call arguments, are swapped back, so the model provider never sees the real value but client tools still get it.

- Fakes are an HMAC of the real value keyed from `LITELLM_SALT_KEY`, so the same secret gets the same fake across turns and replicas and prompt caching still hits. Rotating the salt changes every fake and busts those caches once. If the salt is missing, each pod logs a warning and uses a random key, so fakes differ per replica.
- Secrets we generate ourselves (DB passwords, webhook secrets, service-to-service tokens) should use the `sl_` prefix plus letters and digits only, at least 32 characters in total, so they are caught too. Generate one with `task sops:gen-key` (64 by default; `length=32` for apps that cap password length). LiteLLM virtual keys must start with `sk-`, which is already caught.
- The map from fake to real is kept per virtual key for an hour, so a fake the model echoes from an earlier turn (`previous_response_id`, compaction) is still swapped back, whichever replica serves it. Each pod keeps its own map in memory (capped at 2000 fakes) and shares it through `litellm-valkey`:
  - Entries live in one hash per virtual key under `litellm:secret-masking:v1:`, with a per-field 1h TTL (`HSETEX`, Valkey 9+). The key name and field names are HMACs of the virtual key and the fake; the value is AES-GCM encrypted with a key derived from `LITELLM_SALT_KEY` via HKDF, bound to its key and field. Only ciphertext is stored, and each entry expires after an hour.
  - Writes are queued and sent in the background. The read starts at pre-call and runs while the provider works; the reply only waits for it (at most 0.5s) if it has not finished.
  - It is best effort. If Valkey is down or slow, the pod logs the exception type once, stops trying for 15s and restores from its own memory only. Rotating the salt makes old entries unreadable; they are skipped and expire.
- WebSocket upgrades on the `litellm` host are denied at Traefik with a 403; Responses clients (Codex) fall back to HTTP streaming. Revisit the block once [BerriAI/litellm#40591](https://github.com/BerriAI/litellm/issues/40591) is resolved.
- It is a required middleware: if it fails to import, LiteLLM fails to start, so a broken rollout crash-loops the new pod while the old pods keep serving.

### Guardrails

`pii-protection` (Presidio sidecars), `prompt-injection` (llm-guard sidecar) and `jev-compaction` (TypeSafe, external) are all `default_on: false`: a caller must opt in per request or per key. `jev-compaction` sends tool output to an external service, so keep it opt-in.

The Presidio and llm-guard Deployments are parked at `replicas: 0` (#3323): nothing opts in, and their false-positive rate makes them unusable for Claude traffic on a global toggle. Config, VPAs, network policies and the `llm-guard-hf-cache` PVC are kept, so set `replicas: 1` on all three controllers in `values.yaml` to bring them back. While parked, a request that does opt in to `pii-protection`
or `prompt-injection` fails rather than skipping the check: neither sets `unreachable_fallback: fail_open`.

`llm-tool-guard` is the scanner behind the `tool-guard` middleware (see Proxy middleware), a separate Deployment from llm-guard and not a LiteLLM guardrail. It serves `POST /v1/scan` on port 8080 and scores tool-result text with `Horizon-Labs/prompt-injection-guard-base` in overlapping token windows. The model loads from the `llm-tool-guard-hf-cache` PVC at `HF_HOME`, and the pod becomes ready
once it has loaded. Verdicts are cached by content hash in `litellm-valkey` under `llm-tool-guard:` through the `llm-tool-guard` ACL user, so a result gets the same verdict on every turn. Only LiteLLM pods (and vmagent, for metrics) can reach the scanner, and it reaches `litellm-valkey` and has HTTPS egress for Hugging Face model downloads. It runs with `HF_HUB_OFFLINE`, so it loads the model from
the `llm-tool-guard-hf-cache` PVC. If the PVC is replaced, remove `HF_HUB_OFFLINE` from `values.yaml` to re-download the model, then restore it. Metrics (`llm_tool_guard_*`) are scraped from `/metrics`, and the `LLMToolGuardUnavailable` alert fires when no pod is ready.

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
