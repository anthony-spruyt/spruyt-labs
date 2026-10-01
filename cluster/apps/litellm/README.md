# LiteLLM Proxy - LLM and MCP Gateway

## Overview

Single gateway for every LLM call and most MCP traffic in the cluster: Claude agent pods, Coder workspaces, n8n and dev containers all point `ANTHROPIC_BASE_URL` at it. It exposes Anthropic-compatible (`/v1/messages`) and OpenAI-compatible (`/v1/chat/completions`) APIs plus an MCP gateway at `/mcp`. `litellm-valkey` is its dedicated cache and router-state store; `litellm/app/plugins/middleware/`
holds proxy-side Python middleware.

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

### Database credentials

The `litellm` Postgres login is ESO-generated (`sl_` prefix) into `litellm-cnpg-owner` by `litellm/app/cnpg-roles-eso.yaml`; nothing is in SOPS and superuser access is off. `bootstrap.initdb.secret` points CNPG at it, so CNPG no longer generates `litellm-cnpg-cluster-app`. `DATABASE_URL` interpolates `LITELLM_DB_PASSWORD` (`dependsOn` orders it first).

The database is deliberately not a db-mcp source: it holds virtual keys, stored provider credentials and MCP server tokens. Use `kubectl cnpg psql litellm-cnpg-cluster -n litellm -- -d litellm`.

To rotate, delete both the Secret and the ExternalSecret (`kubectl -n litellm delete secret,externalsecret litellm-cnpg-owner`). Flux recreates the ExternalSecret with a new password and CNPG applies it. Then `kubectl -n litellm rollout restart deploy/litellm` - Reloader ignores a recreated Secret, and agents routed through LiteLLM lose it until the restart.

### Valkey credentials

`litellm-valkey` ACL passwords live in `litellm-valkey-users`, which only ESO writes: `litellm-valkey/app/users-eso.yaml` has one `sl_`-prefixed `CreatedOnce` ExternalSecret per user. Nothing is in SOPS. Valkey has Reloader auto mode, so it restarts when that secret changes; the LiteLLM pods restart too because `REDIS_PASSWORD` reads it.

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

Omit cost params for models LiteLLM already prices in its bundled `model_prices_and_context_window.json` (all current Claude models). Only set `input_cost_per_token` / `output_cost_per_token` for models absent from that registry, such as OpenRouter entries.

Only live models are registered. Retired names are deliberately left unmapped so they fail fast with a clear error rather than silently routing somewhere unintended.

### MCP servers

MCP servers are registered through the LiteLLM UI and persisted in Postgres (the one DB object type allowed above), not in `config.yaml`. On a rebuild they must be re-added by hand; see [unifi-network-mcp](../unifi-mcp/unifi-network-mcp/README.md#litellm-registration-is-manual) for the reasoning. For each in-cluster MCP server, LiteLLM needs an egress CNP in `litellm/app/network-policies.yaml` and
the server needs an ingress CNP from the `litellm` namespace. `.mcp.json` in the repo root holds a single `litellm` entry; every downstream server is fanned out through it.

### Proxy-side plugins

`litellm/app/plugins/middleware/` is mounted into the pod from the `litellm-middleware-plugin` ConfigMap as subPath files under `/app/custom_callbacks/middleware/`, with an init container creating the package directories. `middleware/pipeline_plugin.py` is the single callback registered in `config.yaml`; it runs the middlewares listed in `middleware/registry.py`. Only `secret-masking` and
`ratelimit-headers` are in `DEFAULT_MIDDLEWARE_SPECS`, so `middleware/hindsight/` and `middleware/chatgpt/` are inert even though their files are still mounted. To enable one, add a `MiddlewareSpec` for it; order matters (Hindsight before ChatGPT, because Hindsight injects into Anthropic `system` and ChatGPT then translates the final system content). Run the unit tests with
`task test:litellm-middleware`.

### Adding a middleware

Every proxy-side callback is a middleware run by the pipeline; nothing else goes in `plugins/`. The top of `middleware/` holds only the shared pipeline core, and every middleware gets its own sub-folder:

```text
middleware/
  base.py  pipeline.py  pipeline_plugin.py  registry.py
  tests/                  core tests only
  <name>/
    __init__.py           empty
    <name>.py             module-level instance that registry.py loads
    <helper>.py           used by this middleware only
    tests/test_<name>.py
```

- `<name>` is the snake_case form of the registry name (`secret-masking` → `secret_masking/`). Nothing specific to one middleware goes at the top level, including its tests.
- One `pyproject.toml` and `uv.lock` for all of `middleware/`. Add test-only deps there; runtime deps must already ship in the LiteLLM image.
- ConfigMap keys are flat, so file names must be unique across all middlewares.
- Import the core with `from ..pipeline import ...` and helpers with `from .<helper> import ...`. No flat-import fallbacks.
- Tests put `plugins/` on `sys.path` and import `middleware.<name>.<name>`, the same package shape as in the pod.
- Register it in `registry.py` as `custom_callbacks.middleware.<name>.<name>`. Use `required=True` only when serving without it is unsafe.
- Wire every file into the pod: a ConfigMap generator entry in `kustomization.yaml`; the `/app/custom_callbacks/middleware/<name>` directory in the init container's `mkdir`; a subPath mount in `values.yaml` for each file, plus the shared empty `__init__.py`.
- Add `<name>/tests` to `testpaths` in `middleware/pyproject.toml` and `plugins/pytest.ini`, and to `sonar.tests` in `.sonarcloud.properties`.
- Add the module to `tests/test_production_imports.py` so the in-pod import path is tested.
- Give it a `###` section in this README if anything about it is non-obvious.

### Rate-limit headers

LiteLLM renames every non-OpenAI upstream header to `llm_provider-<name>` and has no setting to turn that off, so Claude Code never sees `anthropic-ratelimit-unified-*` and its status line gets `rate_limits: null`. `middleware/ratelimit_headers/` adds un-prefixed copies of that header family only, from `async_post_call_response_headers_hook`, and leaves the prefixed ones in place.

- Streamed replies: read from `response._hidden_params["additional_headers"]`. Non-streamed replies: the proxy pops `_hidden_params` from dict responses before the hook runs, so the raw upstream headers are read from `data["litellm_logging_obj"].model_call_details["httpx_response"]`.
- LiteLLM only calls the hook if the callback's own class defines it (a leaf `__dict__` check), so `MiddlewarePipeline` must define `async_post_call_response_headers_hook` itself, not inherit it.
- Not covered: error replies (429s) and the opt-in `LITELLM_RUST` `/v1/messages` path, which sets neither header source.
- It is optional in `registry.py`: an import failure logs a warning and the proxy serves without it.
- Remove it once LiteLLM forwards `anthropic-ratelimit-unified-*` unprefixed or adds a setting to do so.

### Secret masking

`middleware/secret_masking/` is always on for `/v1/messages`, `/v1/chat/completions`, `/v1/responses`, `/v1/responses/compact`, `/v1/completions` and Gemini `generateContent`/`streamGenerateContent`, and for the body that `count_tokens`/`input_tokens` forward to the provider. Credentials with a known prefix (GitHub, Google, Anthropic, OpenAI, AWS, LiteLLM `sk-`, PEM private keys and others in
`_PATTERNS`) are swapped for a fake with the same prefix, length and character classes before the request leaves the proxy. Fakes in the reply, including streamed text and tool-call arguments, are swapped back, so the model provider never sees the real value but client tools still get it.

- Fakes are an HMAC of the real value keyed from `LITELLM_SALT_KEY`, so the same secret gets the same fake across turns and replicas and prompt caching still hits. Rotating the salt changes every fake and busts those caches once. If the salt is missing, each pod logs a warning and uses a random key, so fakes differ per replica.
- Secrets we generate ourselves (DB passwords, webhook secrets, service-to-service tokens) should use the `sl_` prefix plus letters and digits only, at least 32 characters in total, so they are caught too. Generate one with `task sops:gen-key` (64 by default; `length=32` for apps that cap password length). LiteLLM virtual keys must start with `sk-`, which is already caught.
- Only prefixed formats are caught. Bare high-entropy strings (hashes, UUIDs, unprefixed passwords) pass through on purpose, to avoid mangling commit SHAs and similar.
- Thinking and reasoning blocks, base64 sources, `data:` URLs, `input_audio` and remote image/file URLs are never touched: thinking signatures would break, binary payloads would be corrupted, and presigned URLs would stop working.
- The map from fake to real is kept per virtual key for an hour, so a fake the model echoes from an earlier turn (`previous_response_id`, compaction) is still swapped back, whichever replica serves it. Each pod keeps its own map in memory (capped at 2000 fakes) and `middleware/secret_masking/shared_fakes.py` shares it through `litellm-valkey`:
  - Entries live in one hash per virtual key under `litellm:secret-masking:v1:`, with a per-field 1h TTL (`HSETEX`, Valkey 9+). The key name and field names are HMACs of the virtual key and the fake; the value is AES-GCM encrypted with a key derived from `LITELLM_SALT_KEY` via HKDF, bound to its key and field. Nothing readable is stored, but the ciphertext does sit in the AOF on the PVC for up to
    an hour.
  - Writes are queued and sent in the background. The read starts at pre-call and runs while the provider works; the reply only waits for it (at most 0.5s) if it has not finished.
  - It is best effort. If Valkey is down or slow, the pod logs the exception type once, stops trying for 15s and restores from its own memory only. Rotating the salt makes old entries unreadable; they are skipped and expire.
- WebSocket traffic is not covered. In Responses WebSocket mode only the first `response.create` frame goes through the hooks, and the other sockets (`/openai/*` passthrough, which can also carry Responses, realtime, `/anthropic/ws`) are not on the list above. So the Traefik route blocks every WebSocket upgrade on the `litellm` host with a 403, and Responses clients (Codex) fall back to HTTP
  streaming, which is masked. In-cluster callers that use the `litellm` service directly bypass Traefik and are not blocked. Remove the block once LiteLLM can disable Responses WebSocket mode ([BerriAI/litellm#40591](https://github.com/BerriAI/litellm/issues/40591)) or hooks every frame.
- The module is `required` in `registry.py`: if it fails to import, LiteLLM fails to start rather than serving unmasked, so a broken rollout crash-loops the new pod while the old pods keep serving.
- Once loaded, it fails open. A bug logs a warning and the traffic flows unmasked rather than failing. Mid-stream, the rest of the stream passes through raw, so the client may see fakes from that point on. If an error escapes a streaming middleware after it has sent output, the pipeline ends the stream with an error instead, because replaying would drop or duplicate buffered data.
- It protects the model provider only. LiteLLM captures the request for its own logging (OTEL traces) before the hook runs, so treat those as holding real values.

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
