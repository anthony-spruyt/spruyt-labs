# LiteLLM Proxy - Centralized LLM Gateway

## Overview

LiteLLM Proxy provides a centralized, OpenAI-compatible LLM gateway backed by Alibaba Cloud Model Studio (DashScope). Routes multiple model providers (Qwen, DeepSeek, Zhipu GLM, MiniMax, Kimi) through a single gateway. Replaces direct Anthropic API usage for Claude Code CLI automation, providing virtual key management, spend tracking, and OTEL observability.

## Prerequisites

- authentik (SSO via OIDC Blueprint)
- cnpg-operator (CloudNativePG)
- external-secrets (cross-namespace OIDC credential sync)
- plugin-barman-cloud (CNPG backup plugin)

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

| Consumer         | Secret Location                                       | Key Name               |
| ---------------- | ----------------------------------------------------- | ---------------------- |
| n8n agent pods   | `mcp-credentials` in each `claude-agents-*` namespace | `litellm-api-key`      |
| Coder workspaces | Per-developer workspace secret or `.env`              | `ANTHROPIC_AUTH_TOKEN` |

### Authentik SSO

LiteLLM uses built-in OIDC SSO (not Authentik outpost). The OIDC provider and application are deployed declaratively via Authentik Blueprint (`blueprints/litellm-sso.yaml`). Credentials are synced cross-namespace via ExternalSecret (same pattern as Coder, Grafana, Vaultwarden).

Blueprint creates:

- Groups: `LiteLLM Users` (parent), `LiteLLM Admins` (child)
- Provider: OAuth2/OIDC, confidential client
- Application: slug `litellm`, redirect URI `/sso/callback`
- Policy binding: restricts access to `LiteLLM Users` group members

### Model Management

Model routing is managed via CNPG DB (`LiteLLM_ProxyModelTable`), not config.yaml. All models are registered via the LiteLLM Admin API (`POST /model/new`) or UI.

When adding a new Claude alias, create **two entries** — one for each DashScope protocol endpoint:

| Order | Protocol     | Endpoint                          | Used By                            |
| ----- | ------------ | --------------------------------- | ---------------------------------- |
| 1     | `anthropic/` | `/apps/anthropic` (code plan)     | Claude Code, Anthropic API clients |
| 2     | `openai/`    | `/compatible-mode/v1` (code plan) | LiteLLM UI, OpenAI API clients     |

DashScope provides two endpoints per billing tier:

- **OpenAI-compatible**: `https://<host>/compatible-mode/v1`
- **Anthropic-compatible**: `https://<host>/apps/anthropic`

Both code plan (`token-plan.ap-southeast-1.maas.aliyuncs.com`) and PAYG (`dashscope-intl.aliyuncs.com`) expose both protocols.

**Adding models via API:**

```bash
kubectl exec -n litellm deployment/litellm -- python3 -c "
import urllib.request, json, os
key = os.environ.get('LITELLM_MASTER_KEY', '')
payload = json.dumps({
    'model_name': 'your-alias',
    'litellm_params': {'model': 'provider/actual-model', 'api_key': 'os.environ/API_KEY'},
    'model_info': {'input_cost_per_token': 0.0, 'output_cost_per_token': 0.0}
}).encode()
req = urllib.request.Request('http://localhost:4000/model/new', data=payload, headers={
    'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'
})
print(urllib.request.urlopen(req).read().decode()[:100])
"
```

### Headroom Context Compression

The `headroom` controller is a compression sidecar. The proxy never routes traffic to it — the `headroom-compression` guardrail POSTs the message array to its `/v1/compress` during the `pre_call` hook and substitutes the returned messages before forwarding upstream.

It is **opt-in** (`default_on: false`). Attach it to a virtual key:

```bash
curl -X POST "http://litellm.litellm.svc.cluster.local:4000/key/update" \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"key": "sk-...", "guardrails": ["headroom-compression"]}'
```

Or per request — `"guardrails": ["headroom-compression"]` in an OpenAI-format body, or `"litellm_metadata": {"guardrails": [...]}` on `/v1/messages`, which has no top-level guardrails field. Send header `x-headroom-bypass: true` to skip compression for one call.

Verify it ran via the `x-litellm-applied-guardrails: headroom-compression` response header, or the `guardrail_information` field on the spend log row.

Deployment notes not covered by the upstream guide, both confirmed against the sidecar source:

| Setting                             | Why it is required                                                                                                                                        |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `HEADROOM_COMPRESS_ALLOW_REMOTE=1`  | `/v1/compress` carries a loopback-only dependency by default, so an in-cluster caller gets 404. Only this route is exposed; inbound auth still applies.   |
| `HEADROOM_SKIP_UPSTREAM_CHECK=1`    | `/readyz` HEAD-probes the upstream provider API. Nothing here proxies to a provider, so the check would keep the pod permanently unready.                 |
| `HEADROOM_COMPRESS_USER_MESSAGES=1` | User/system rows are skipped by default. Anthropic-format requests translate to user-role rows, so without this most traffic passes through uncompressed. |
| `HEADROOM_WORKSPACE_DIR`            | Relocates the read-write state root off `$HOME` onto the cache PVC.                                                                                       |

Messages carrying an Anthropic `cache_control` marker are never compressed — there is no override, because rewriting them would break prompt-cache prefix matching.

`unreachable_fallback: fail_open` is deliberate: the upstream default (`fail_closed`) turns an unreachable sidecar into a 502 on every opted-in request. Compression is an optimisation, so a failure should cost tokens, not availability.

### Known Issues

| Issue                 | Description                                            | Mitigation                                      |
| --------------------- | ------------------------------------------------------ | ----------------------------------------------- |
| BerriAI/litellm#25868 | Tool results silently dropped (list-format content)    | Monitor, wait for upstream fix                  |
| BerriAI/litellm#27839 | Multi-turn conversations may get stuck                 | Retry logic in consumers                        |
| Anthropic passthrough | `openai/` models fail on `/v1/messages` endpoint       | Use `anthropic/` entries at higher priority     |
| Claude Code cost_usd  | Broken — internal price table only knows Claude models | Use LiteLLM Grafana dashboard for cost tracking |
| Cache tokens          | Zero — models may lack prompt caching                  | Expected behavior                               |

### Security: PyPI Supply Chain Advisory

LiteLLM PyPI versions 1.82.7-1.82.8 were compromised. **NEVER install from PyPI.** Docker/GHCR images were NOT affected. Always pin to a specific version tag with digest.

## Troubleshooting

1. **LiteLLM fails to start — database connection error**

   - **Symptom**: Pod CrashLoopBackOff, logs show "connection refused" to PostgreSQL
   - **Resolution**: Verify CNPG cluster is healthy: `kubectl get cluster -n litellm`. The CNPG cluster must be `Ready` before LiteLLM starts. Check that `litellm-cnpg-cluster-app` secret exists.

2. **SSO redirect loop**

   - **Symptom**: Login redirects endlessly between LiteLLM and Authentik
   - **Resolution**: Verify `PROXY_BASE_URL` matches the IngressRoute hostname exactly. Check Authentik Application redirect URI includes `/sso/callback`.

3. **Alibaba Cloud Model Studio API errors**

   - **Symptom**: 401/403 from upstream provider
   - **Resolution**: Verify `DASHSCOPE_API_KEY` in litellm-secrets. Check Alibaba Cloud Model Studio subscription status and quota.

## References

- [LiteLLM Documentation](https://docs.litellm.ai/)
- [LiteLLM Headroom Guardrail](https://docs.litellm.ai/docs/proxy/headroom)
- [Headroom](https://github.com/headroomlabs-ai/headroom)
- [LiteLLM DashScope Provider](https://docs.litellm.ai/docs/providers/dashscope)
- [Alibaba Cloud Model Studio](https://www.alibabacloud.com/en/product/model-studio)
- [Claude Code LLM Gateway Docs](https://code.claude.com/docs/en/llm-gateway)
- [PyPI Compromise Advisory](https://github.com/BerriAI/litellm/issues/24524)
