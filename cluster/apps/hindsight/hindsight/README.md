# Hindsight - Proxy-Side Long-Term Memory

## Overview

Long-term memory for anything routed through LiteLLM, with no client changes: a LiteLLM middleware recalls memories before each call and retains the exchange afterwards. The Hindsight API stores them in its own CNPG cluster (#1890).

> **Dormant.** The api, worker and controlPlane are at `replicaCount: 0`, the CNPG cluster is hibernated (`cnpg.io/hibernation: "on"`), its ScheduledBackup is suspended, and the LiteLLM middleware is not registered in `litellm/litellm/app/plugins/middleware/registry.py`. The component is slated for removal (#3025). Nothing below is active until it is revived.

## Operations

### Reviving it

Every item is required; skipping one leaves it broken in a non-obvious way.

1. `app/hindsight-cnpg-cluster.yaml`: set `cnpg.io/hibernation` to `"off"` and `monitoring.enablePodMonitor` to `true` (it is off because an empty scrape pool fires `ScrapePoolHasNoTargets`).
2. `app/hindsight-cnpg-scheduled-backups.yaml`: set `suspend: false`.
3. `ks.yaml`: restore `wait: true`. It is `false` only because a hibernated cluster never reports Ready and `traefik-ingress` depends on this Kustomization.
4. `app/values.yaml`: scale api, worker and controlPlane back up. Bring the api to 1 first so only one node cold-pulls the ~1.4 GB image; Spegel fans it out before you go to 2. Re-enable the PDBs only once replicas are above 1.
5. LiteLLM: re-register the `hindsight-model` and `hindsight-embedding` aliases in `config.yaml`. They were removed (#3025), so the api and worker will get 400s from LiteLLM without them.
6. LiteLLM: add a `MiddlewareSpec(name="hindsight", module="custom_callbacks.hindsight.hindsight_plugin", attribute="hindsight_middleware")` to `DEFAULT_MIDDLEWARE_SPECS` in `middleware/registry.py`. Keep it before `chatgpt` — Hindsight injects into the Anthropic `system` field and the ChatGPT middleware then translates the final system content.
7. Check that `HINDSIGHT_API_CONSOLIDATION_LLM_MODEL` in `values.yaml` still names a model LiteLLM serves; it was not updated when older Claude models were retired.

### Bank selection

Memory is keyed by a **bank** (one logical store, e.g. one per repo), resolved per request, first match wins:

1. Request header `x-hindsight-bank`
2. Virtual-key metadata `hindsight_bank`
3. Team metadata `hindsight_bank`
4. **None → skip memory entirely** (no shared default bank — prevents cross-repo contamination)

The value is sanitized to `[A-Za-z0-9-]`. For Claude Code, add `x-hindsight-bank: <repo>` to `ANTHROPIC_CUSTOM_HEADERS` alongside the LiteLLM key header.

### Middleware behaviour

- Both recall and retain **fail open**: errors and timeouts are logged and swallowed.
- Memory is injected as the **last** Anthropic `system` block so the cached prompt prefix is preserved. Watch prompt-cache metrics after changing injection.
- Recall runs inline and slows as the bank grows (2.4-3.5s at ~30 facts), which exceeds the plugin's 3s default; `HINDSIGHT_TIMEOUT_S` is raised to 30 on the LiteLLM container for that reason.
- Each exchange is retained as one item whose `content` is a JSON conversation array. That shape is what makes `HINDSIGHT_API_RETAIN_STRUCTURED_CHUNK_SIZE` (8192) apply; a bare string is split at the 3000-char default and fragments memories.
- Other plugin env vars and their defaults are at the top of `HindsightMiddleware.__init__` in `litellm/litellm/app/plugins/hindsight/hindsight_plugin.py`.

### Extraction tuning

Retain settings in `app/values.yaml` are tuned for coding sessions (#2270): whole-turn chunks, `verbose` extraction, and a coding-focused `RETAIN_MISSION`. Per-turn auto-consolidation is off; `app/consolidate-cronjob.yaml` consolidates every bank nightly instead, so the heavier consolidation model runs once a day rather than per turn.

## Troubleshooting

1. **api or worker crash-loops at ~50s with no useful log**

   - **Cause**: The egress CNP allows only Postgres and LiteLLM. Without offline mode, transformers does an online check against huggingface.co that hangs until the liveness probe kills the pod.
   - **Fix**: Keep `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1` on both api and worker; the reranker model is baked into the image.

2. **Worker crashes with `invalid literal for int(): 'tcp://...'`**

   - **Cause**: The `hindsight-api` Service makes Kubernetes inject `HINDSIGHT_API_PORT=tcp://...` into every pod.
   - **Fix**: Keep the explicit `HINDSIGHT_API_PORT: "8888"` in `worker.env`.

3. **`422` on retain**

   - **Cause**: `MemoryItem.context` must be a string; the conversation array belongs in `content`.

4. **No memory injected**

   - **Cause**: No bank resolved, which is an intentional skip. Confirm the header reaches LiteLLM or the key/team has `hindsight_bank` metadata.

## References

- [Hindsight](https://github.com/vectorize-io/hindsight)
