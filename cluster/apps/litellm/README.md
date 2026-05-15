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

### Model Protocol Configuration

Claude Code sends requests via the Anthropic Messages API (`/v1/messages`). LiteLLM's Anthropic passthrough (`experimental_pass_through`) cannot properly translate `openai/` prefixed models — requests fail with `Unsupported model` or streaming event order errors.

**Every Claude alias must have both protocol entries:**

| Order | Protocol     | Endpoint                          | Used By                            |
| ----- | ------------ | --------------------------------- | ---------------------------------- |
| 1     | `anthropic/` | `/apps/anthropic` (PAYG)          | Claude Code, Anthropic API clients |
| 2     | `anthropic/` | `/apps/anthropic` (code plan)     | Fallback                           |
| 3     | `openai/`    | `/compatible-mode/v1` (PAYG)      | LiteLLM UI, OpenAI API clients     |
| 4     | `openai/`    | `/compatible-mode/v1` (code plan) | Last resort                        |

DashScope provides two endpoints per billing tier:

- **OpenAI-compatible**: `https://<host>/compatible-mode/v1`
- **Anthropic-compatible**: `https://<host>/apps/anthropic`

Both code plan (`token-plan.ap-southeast-1.maas.aliyuncs.com`) and PAYG (`dashscope-intl.aliyuncs.com`) expose both protocols.

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

1. **SSO redirect loop**

   - **Symptom**: Login redirects endlessly between LiteLLM and Authentik
   - **Resolution**: Verify `PROXY_BASE_URL` matches the IngressRoute hostname exactly. Check Authentik Application redirect URI includes `/sso/callback`.

1. **Alibaba Cloud Model Studio API errors**

   - **Symptom**: 401/403 from upstream provider
   - **Resolution**: Verify `DASHSCOPE_API_KEY` in litellm-secrets. Check Alibaba Cloud Model Studio subscription status and quota.

## References

- [LiteLLM Documentation](https://docs.litellm.ai/)
- [LiteLLM DashScope Provider](https://docs.litellm.ai/docs/providers/dashscope)
- [Alibaba Cloud Model Studio](https://www.alibabacloud.com/en/product/model-studio)
- [Claude Code LLM Gateway Docs](https://code.claude.com/docs/en/llm-gateway)
- [PyPI Compromise Advisory](https://github.com/BerriAI/litellm/issues/24524)
