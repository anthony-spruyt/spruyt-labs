# LiteLLM Proxy - LLM and MCP Gateway

## Overview

Single gateway for every LLM call and most MCP traffic in the cluster: Claude agent pods, Coder workspaces, n8n and dev containers all point `ANTHROPIC_BASE_URL` at it. It exposes Anthropic-compatible (`/v1/messages`) and OpenAI-compatible (`/v1/chat/completions`) APIs plus an MCP gateway at `/mcp`. `litellm-valkey` is its dedicated cache and router-state store. Proxy-side Python middleware comes
from [`anthony-spruyt/litellm-middleware`](https://github.com/anthony-spruyt/litellm-middleware).

## Prerequisites

- Authentik OAuth provider, secret and rotation wiring — see [authentik README](../authentik-system/authentik/README.md#oauth-credential-rotation).
- Provider API keys in `litellm/app/litellm-secrets.sops.yaml`, referenced from `config.yaml` as `os.environ/<NAME>`. The `anthropic/*` models set no `api_key`; they are subscription passthrough (below). The `anthropic-api/*` fallback models set `api_key: os.environ/ANTHROPIC_API_KEY`.
- `TOOL_GUARD_TEAM_IDS` in the same secret: the comma-separated LiteLLM team IDs whose requests the tool-guard middleware enforces.
- `HF_TOKEN` in `litellm-secrets`, for the llm-guard model download.
- The Brave search tool's `BRAVE_API_KEY` comes from `litellm-brave`, not `litellm-secrets`. `litellm/app/brave-secret-store.yaml` copies it from `brave-search-secrets` in `brave-search-mcp` into `litellm-brave` every 5m through ESO, and the container reads it from there. Rotate it in that one SOPS file; see the [brave-search-mcp README](../brave-search-mcp/brave-search-mcp/README.md).

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

The database is deliberately not a db-mcp source: it holds virtual keys, stored provider credentials and the UI-managed MCP server's token. Use `kubectl cnpg psql litellm-cnpg-cluster -n litellm -- -d litellm`.

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

Adding a Claude model takes five edits in `values.yaml`:

| Key                                 | Entry                                                                  | Why                                                                          |
| ----------------------------------- | ---------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `model_list`                        | `anthropic/<model>` pointing at itself                                 | Registers the subscription deployment                                        |
| `model_list`                        | `anthropic-api/<model>` with `api_key: os.environ/ANTHROPIC_API_KEY`   | Registers the API-key deployment used as fallback                            |
| `router_settings.model_group_alias` | `<model>` → `anthropic/<model>`                                        | Lets clients send the bare name Claude Code uses                             |
| `router_settings.fallbacks`         | `anthropic/<model>` → `["anthropic-api/<model>"]`                      | Retries on the API key when a subscription call fails                        |
| `router_settings.fallbacks`         | each alias other than the bare `<model>` → `["anthropic-api/<model>"]` | LiteLLM looks up fallbacks by the name the client sent, not the alias target |

When a subscription call fails (for example a 429 at the weekly limit), the router retries it on the matching `anthropic-api/<model>` deployment. The `fallback-auth` middleware (see Proxy middleware) removes the client's own login credentials from that retry, so the call uses `ANTHROPIC_API_KEY`. LiteLLM sets no budget on these deployments; the Anthropic API account has a fixed monthly credit and
no card, so spend stops there.

The `*claude*opus*` / `*claude*sonnet*` / `*claude*haiku*` catch-all deployments (below) have no fallback entry.

`general_settings.enforce_fallback_model_access: true` makes the router attempt a fallback only when the caller's key and team may call the fallback model. A team limited to explicit `models` lists the `anthropic-api/<model>` names it falls back to.

LiteLLM loads the upstream `main` `model_prices_and_context_window.json` at startup over the world HTTPS egress, falling back to the copy bundled in the image. Omit cost params for models that map prices (all current Claude models, including some the pinned image doesn't bundle yet). Only set `input_cost_per_token` / `output_cost_per_token` for models absent from it, such as OpenRouter entries.

Only live models are registered. Retired Opus, Sonnet and Haiku names are not rejected, because some clients can't change the model they send. `model_group_alias` maps the known ones (including the Haiku 4.5 names) to the 5.5 groups, and the `*claude*opus*` / `*claude*sonnet*` / `*claude*haiku*` catch-all deployments send any other name containing those substrings to Opus 5.5 / Sonnet 5.5 / Haiku
5.5. That includes other providers' names such as `openrouter/anthropic/claude-opus-4.1`. LiteLLM tries aliases, then exact `model_name`s, then wildcards, so a newly registered model is never shadowed by a catch-all. Matching is case-sensitive.

### External access for CI

CI on GitHub-hosted runners calls the `litellm` host over the Cloudflare tunnel (`infra/terraform/cloudflare`, see its [README](../../../infra/terraform/cloudflare/README.md#litellm-external-access-for-ci)). On the LAN the host resolves straight to Traefik, so the UI, SSO and MCP work as before.

- Only `/v1/messages`, `/v1/messages/count_tokens`, `/v1/chat/completions` and `/health/liveliness` pass from the internet. Unprefixed aliases such as `/chat/completions` do not.
- cloudflared forwards only those paths and requires a valid Access token before a request reaches Traefik.
- Every request carries the Access service token headers `CF-Access-Client-Id` and `CF-Access-Client-Secret`, plus the CI virtual key in `x-litellm-api-key: Bearer <key>` (see Virtual keys above).
- The CI models are the exact `model_name`s listed under team `github-ci` in `access-policy.yml`. A Claude model must keep its exact `openrouter/` name: the `*claude*haiku*` catch-all would route a looser name to Anthropic subscription passthrough, which rejects a virtual key. The CI virtual key belongs to team `github-ci` with `models: ["all-team-models"]` and
  `object_permission: {"mcp_servers": ["no-mcp-servers"]}`; the team's models and budget are set in `access-policy.yml` (see Access policy).

### MCP servers

MCP servers are declared under `mcp_servers:` in `config.yaml` (`litellm/app/values.yaml`, `configMaps.litellm-config`). Only `n8n` is still registered through the LiteLLM UI and persisted in Postgres, which is why `mcp` stays in `supported_db_objects`. Config-defined servers show in the UI as read-only; edit `values.yaml` instead.

Each entry pins `server_id` and `alias`. Teams and access groups grant tools by server id, and tool names carry the alias as a prefix, so changing either breaks those grants and renames the tools. A DB row with the same `server_id` shadows the config entry, so delete the row once the entry is live.

Tokens are `authentication_token: os.environ/MCP_<NAME>_TOKEN`, read once at startup from `litellm-secrets` (SOPS, mounted with `envFrom`). Add the key with `sops`; Reloader restarts the pods when the Secret changes.

To add a server:

1. Add an entry to `mcp_servers` with a fresh UUID `server_id`, `alias` equal to the key, `url`, `transport`, `auth_type`, `allowed_tools`, `disallowed_tools` (every other tool the server offers, or the drift Job opens an issue) and `available_on_public_internet: false`.
2. For a bearer-token server, add `MCP_<NAME>_TOKEN` to `litellm-secrets`.
3. Add an egress CNP in `litellm/app/network-policies.yaml` and, for an in-cluster server, an ingress CNP that matches the proxy pods in the `litellm` namespace by both `app.kubernetes.io/name: litellm` and `app.kubernetes.io/controller: litellm`.
4. Grant the server to teams or access groups in `litellm/access-policy/access-policy.yml` (see Access policy).

`.mcp.json` in the repo root holds a single `litellm` entry; every downstream server is fanned out through it.

### Access policy

Team settings (models, budget, MCP access) and access groups are declared in `litellm/access-policy/access-policy.yml` and applied by the `litellm-access-policy` Job, which calls the admin API with the master key from `litellm-secrets`. The file holds:

| Section         | Matched by | Managed fields                                                                            |
| --------------- | ---------- | ----------------------------------------------------------------------------------------- |
| `teams`         | `team_id`  | `team_alias`, `object_permission`, `models`, `max_budget` and `budget_duration`           |
| `access_groups` | `name`     | `description`, `models`, `mcp_server_ids`, `agent_ids`, `team_ids` (unified access group) |

- Every team lists `models`, a non-empty list: the exact set of model names the team may request, matched against the requested name or its router alias target. An empty list would allow every model, so it is rejected. Use `all-proxy-models` for a team that may call everything.
- `max_budget` (a number above 0) and `budget_duration` (such as `30d`) are set together or not at all. A team without them has no budget, and a budget set live but missing from the file is removed.
- MCP access is granted on teams and access groups only; a key inherits its team's grants, so keys carry no MCP limits of their own.
- Keys, users and team members, the model list and the `n8n` MCP server stay in the LiteLLM UI/DB.
- A listed object is compared on its managed fields only, and an omitted list field means empty: a grant that exists live but not in the file is a diff. The Job never deletes anything, so objects missing from the file are left alone.
- Access groups match by `name` because LiteLLM generates their ids. Group membership is declared on the group (`team_ids`), not on the team.
- To change policy, edit `access-policy.yml` and push. The ConfigMap name carries a content hash, so the Job spec changes, Flux recreates the Job (`kustomize.toolkit.fluxcd.io/force`) and it runs against the new file. After `ttlSecondsAfterFinished` the Job is removed and Flux recreates it at its next 4h reconcile, so it also runs periodically.
- `MODE` in `job.yaml` is `enforce`: the Job creates missing teams and groups with the file's ids and names, then updates only the differing managed fields (teams, then groups), and ends with `changes: N`. Read it with `kubectl -n litellm logs job/litellm-access-policy`; `changes: 0` means the file already matches live state.
- To preview a change without applying it, set `MODE` to `diff` in `job.yaml` for that push: the Job then only logs one block per object and applies nothing. Set it back to `enforce` afterwards.
- LiteLLM merges an `object_permission` update field by field, so the Job sends an empty value (`[]`, `{}`) to clear a field. It logs aliases, ids and permission fields only, never credentials.
- Unit tests for the script run in CI through `tests/litellm-access-policy.bats`.

### MCP tool drift

The `litellm-mcp-tool-drift` CronJob (`litellm/mcp-tool-drift/`, daily) compares each server in `mcp_servers` with what the server offers now. It reads the rendered `litellm-litellm-config` ConfigMap, asks `/mcp-rest/tools/list?include_disabled_tools=true` for the raw tool names, and flags names in neither `allowed_tools` nor `disallowed_tools` (new) and listed names the server no longer offers
(stale).

Each server has two lists, and every tool it offers belongs in exactly one:

| List               | Meaning                       | Effect in LiteLLM                                                                                             |
| ------------------ | ----------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `allowed_tools`    | Enabled                       | The only list that decides what clients can call                                                              |
| `disallowed_tools` | Reviewed and deliberately off | None while `allowed_tools` is set, since anything not allowed is already hidden; it records the decision only |

To resolve a drift issue, edit `litellm/app/values.yaml`: put each new tool in `allowed_tools` to enable it or in `disallowed_tools` to keep it off, and delete each stale name from whichever list holds it. To enable a tool that was kept off, move it from `disallowed_tools` to `allowed_tools`. The Job closes the issue on its next run.

- `MODE` in `cronjob.yaml` is `enforce`. In `report` mode it only logs; either mode logs one line per server with the upstream, allowed and disallowed counts and the sorted new and stale names (`kubectl -n litellm logs job/<latest job>`). A server that fails to list is logged and the Job exits non-zero after the others finish.
- `MODE: enforce` keeps one open `mcp-tool-drift` issue per drifting server in `anthony-spruyt/spruyt-labs`, titled `chore(litellm): MCP tool drift on <server>`. It creates, edits when the body changes, and comments and closes once the drift is gone. It never edits `allowed_tools` or `disallowed_tools`.
- The GitHub App token is synced into `litellm-github-credentials` through the `github-token-rotation` consumer wiring (`mcp-tool-drift/github-token.yaml`), which has its own narrow `github-token-reader-litellm` Role. The CronJob reads it as `GITHUB_TOKEN`, which `enforce` requires.
- Only names made of letters, digits and `_ . - /` (up to 128 characters) are listed in an issue, at most 100 per section followed by an "and N more" line. The Job log shows the count of names left out.
- Removing the `mcp-tool-drift` label from an issue makes the Job open a new one. Issues for a server removed from `mcp_servers` are not closed by the Job: close them by hand.
- Unit tests run in CI through `tests/litellm-mcp-tool-drift.bats`.

### Proxy middleware

The middleware package ships as the `ghcr.io/anthony-spruyt/litellm-middleware` image, mounted read-only as a Kubernetes `image` volume at `/opt/litellm-middleware`, which is on `PYTHONPATH`. The kubelet pulls it, so the pod needs no egress for it. `litellm_middleware.pipeline_plugin.pipeline_middleware` is the single callback in `config.yaml`. Code, tests, the middleware list and how each
middleware works live in the [middleware repo](https://github.com/anthony-spruyt/litellm-middleware#readme).

- The middleware imports LiteLLM internals that change between releases, so the cluster runs only a LiteLLM the middleware repo's CI has passed. Renovate here doesn't read the registry for the LiteLLM image. The `custom.litellm-middleware-tested` datasource in `renovate-overrides.json5` reads the tag and digest from `litellm-image.yaml` on the middleware repo's `main`. That pin moves only when the
  middleware repo merges a Renovate bump PR, and that PR runs the integration suite against the new LiteLLM. Upgrade by merging the bump there; the matching PR opens here on the next Renovate run. If the new version needs a middleware fix, release that fix first; Renovate groups the LiteLLM and middleware image bumps under `litellm`, so they land in one PR when both are pending.
  `tests/litellm-middleware-contract.bats` checks the callback, mount path and `PYTHONPATH` here against the deployed middleware release. If `litellm-image.yaml` moves or changes shape, the lookup fails and LiteLLM bumps stop (the dashboard shows the lookup failure); they are never untested.
- `tool-guard` sends each new tool result to the `llm-tool-guard` scanner (`TOOL_GUARD_URL`), waiting up to 180 s for the answer (`TOOL_GUARD_TIMEOUT_SECONDS`, set in `values.yaml`). The scanner's VPA keeps its CPU request at 2 cores or more, because scans are CPU-bound and take up to about 45 s. It marks those it flags, could not check, or that are too big to send (over
  `TOOL_GUARD_MAX_TEXT_BYTES`) with a `<tool-guard-notice>` block that names the verdict (`suspected-prompt-injection`, `unchecked` or `too-big`) and tells the model to treat the output as data, followed by the text inside an `<untrusted-tool-output>` marker. It rewrites only the text, in place in the original request, so fields such as `cache_control` and `is_error` are preserved. It applies to
  the teams listed in `TOOL_GUARD_TEAM_IDS` in `litellm-secrets`; those teams can use only the endpoints the [middleware README](https://github.com/anthony-spruyt/litellm-middleware#tool-guard) lists for enforced keys, and get a client error on any other. For each request with new tool results it writes a `tool-guard` guardrail record: passed, flagged (with the score and the flagged text, capped),
  blocked or cleared by Jev, or failed when results stay unchecked. The record shows in the Logs request drawer and the Guardrails Monitor. The text and tool names need `store_prompts_in_spend_logs: true` (set in `values.yaml`).
  - A result the scanner flags gets a second check from Jev (TypeSafe), which the scanner asks (see Guardrails). Only the middleware's requests ask for it. A result that is too big, or that the scanner could not scan, is not sent to Jev. Jev's answer sets the verdict:
    - Blocked (score at or above `JEV_BLOCK_AT`): each text field of the result is replaced by a `<tool-guard-notice verdict="blocked">` notice that holds none of the original text. The record is `guardrail_intervened` with a `BLOCK` row. A result is blocked only when all of its text can be replaced; otherwise it is recorded as flagged: the text gets the warning notice and marker, and the record
      is `guardrail_flagged` with a `FLAG` row.
    - Cleared (score below `JEV_CLEAR_BELOW`): the original text goes through with no notice. The record is `guardrail_flagged` with a `FLAG` row marked `jev-cleared`.
    - Anything else (a score in between, no answer from Jev, or text over `JEV_MAX_TEXT_BYTES`): the warning notice and marker above, as when the scanner alone flags it.
  - `BLOCK` records count in the Guardrails Monitor's fail rate, so it rises above 0 when a result is blocked. With `LITELLM_OTEL_V2` set (`values.yaml`), LiteLLM also marks the OpenTelemetry span of a `guardrail_intervened` record as an error, although the request still goes to the model.
- `fallback-auth` is an optional middleware. For a call routed to an `anthropic-api/*` deployment it removes the client's `Authorization`, `x-api-key` and `oauth-*` beta tokens, so the deployment's `ANTHROPIC_API_KEY` is used. Without it, LiteLLM sends the forwarded subscription login to Anthropic instead of the key.
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

Tool output the `llm-tool-guard` scanner flags goes to TypeSafe automatically, with no opt-in, for the second check described under Proxy middleware. It goes after `secret-masking` has masked it, because tool-guard runs after secret-masking.

The Presidio and llm-guard Deployments are parked at `replicas: 0` (#3323): nothing opts in, and their false-positive rate makes them unusable for Claude traffic on a global toggle. Config, VPAs, network policies and the `llm-guard-hf-cache` PVC are kept, so set `replicas: 1` on all three controllers in `values.yaml` to bring them back. While parked, a request that does opt in to `pii-protection`
or `prompt-injection` fails rather than skipping the check: neither sets `unreachable_fallback: fail_open`.

`llm-tool-guard` is the scanner behind the `tool-guard` middleware (see Proxy middleware), a separate Deployment from llm-guard and not a LiteLLM guardrail. It serves `POST /v1/scan` on port 8080 and scores tool-result text with `Horizon-Labs/prompt-injection-guard-base` in overlapping token windows. It runs as 2 copies on different nodes where possible (`RollingUpdate` with no unavailable pod, a
PodDisruptionBudget of `minAvailable: 1`, and a 10 s `preStop` sleep so a pod leaves the Service before it stops). The model comes from the `ghcr.io/anthony-spruyt/llm-tool-guard-model` image, mounted read-only as an image volume at `$HF_HOME/hub` over an `emptyDir` `HF_HOME`; a pod becomes ready once it has loaded. Verdicts are cached by content hash in `litellm-valkey` under `llm-tool-guard:`
through the `llm-tool-guard` ACL user, so a result gets the same verdict on every turn. Jev's answers are cached beside them under `llm-tool-guard:jev:`, one answer per result text across both copies, and the thresholds apply when an answer is read, so retuning `JEV_BLOCK_AT` or `JEV_CLEAR_BELOW` asks Jev nothing again. Only LiteLLM pods, the agent-platform worker (for text scans) and vmagent (for
metrics) can reach the scanner, and it reaches `litellm-valkey` and the LiteLLM proxy. It runs with `HF_HUB_OFFLINE`, so it never downloads the model. To change the model revision, bump the weights image tag and digest in `values.yaml` (`llm-tool-guard-model` under `persistence`); the revision pin lives in that image's source in `container-images`, and a new revision, or an `llm-tool-guard`
upgrade that changes the scoring code, starts a fresh verdict-cache namespace. Metrics (`llm_tool_guard_*`) are scraped from `/metrics`; the `LLMToolGuardUnavailable` alert fires when no pod is ready and `LLMToolGuardDegraded` when fewer than 2 are ready for 15 minutes. `LLMToolGuardJevFailing` (expression in `litellm/app/vmrule.yaml`) fires when a question failed and none was answered in the last
6 hours, so one refused text can fire it too. Jev runs only a few times a day, so the alert looks back 6 hours instead of using a rate.

The scanner asks Jev through the gateway's native `/v1/systemone` route, never directly (`JEV_API_URL` in `values.yaml`), so its network policy has no external egress. `JEV_MODE: enforce` turns the second check on; `off` keeps the first model's verdicts as they are. `JEV_MODEL` pins the Jev version and must name a Jev deployment in `model_list`. The cached answers are per model, so changing it
asks Jev again for the results it is shown next. Horizon verdicts stay cached. Keep `JEV_MAX_TEXT_BYTES` well below Jev's per-question token limit: this route wraps Jev's too-long refusal in a LiteLLM error, which the scanner retries after an hour instead of caching for the full TTL.

- The scanner's key is a LiteLLM virtual key in team `llm-tool-guard` (team settings in `access-policy.yml`). It is stored as `JEV_API_KEY` in `llm-tool-guard-secrets` (`litellm/app/llm-tool-guard-secrets.sops.yaml`), and Reloader restarts the scanner when the secret changes. Jev calls fail if this team is added to `TOOL_GUARD_TEAM_IDS`.
- To rotate it, create a new key in the `llm-tool-guard` team in the admin UI, write it to `JEV_API_KEY` with `sops`, and push. Once the scanner pods have rolled, check that they log answered Jev outcomes, then delete the old key. After that, `llm_tool_guard_jev_requests_total{outcome="error"}` should not rise.

The `tool-guard` entry under `guardrails:` is a placeholder: it never runs on its own (no caller opts in) and exists so the Guardrails Monitor detail page for `tool-guard` loads. The records themselves come from the middleware.

`prompt-injection` uses `Horizon-Labs/prompt-injection-guard-base` (ungated), scanning in overlapping 2048-token windows with a 512-token overlap. Inputs over `max_windows` (about 200k tokens) are blocked. llm-guard runs with `HF_HUB_OFFLINE=1` and loads the model from the `llm-guard-hf-cache` PVC. To refill an empty cache, remove `HF_HUB_OFFLINE` from `values.yaml`, let one pod download the model
(the download uses `HF_TOKEN` from `litellm-secrets`), then restore it (Ref #2592, #3464).

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
