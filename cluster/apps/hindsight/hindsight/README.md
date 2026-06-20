# Hindsight Proxy-Side Memory

Transparent long-term memory for any client routed through the LiteLLM proxy (Claude Code CLI, Coder workspaces, agent workers). A LiteLLM `CustomLogger` callback running inside the litellm pod recalls relevant memories before each LLM call and retains the exchange afterwards — **no client code changes**.

- Plugin: `cluster/apps/litellm/litellm/app/plugins/hindsight/hindsight_plugin.py`
- Memory store: `hindsight-api.hindsight.svc.cluster.local:8888`
- Issue: #1890

## How it works

| Phase        | LiteLLM hook              | Action                                                                                                           |
| ------------ | ------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| pre-call     | `async_pre_call_hook`     | RECALL memories for the request's bank, inject as the **last** system block (preserves the cached prompt prefix) |
| post-success | `async_log_success_event` | RETAIN the user prompt + assistant response (async, best effort)                                                 |

Both phases **fail open**: any error or timeout is logged and swallowed, so memory never blocks or degrades the primary completion.

## Enabling memory for a client (bank selection)

Memory is keyed by a **bank** (one logical memory store, e.g. one per repo). The bank is resolved per request, first match wins:

1. Request header `x-hindsight-bank`
2. Virtual-key metadata `hindsight_bank`
3. Team metadata `hindsight_bank`
4. **None → skip memory entirely** (no shared default bank — prevents cross-bank contamination)

The bank value is sanitized to `[A-Za-z0-9-]`.

### Claude Code CLI

Set the custom header to a stable slug (e.g. the repository name). Claude Code already routes to litellm via `ANTHROPIC_BASE_URL`.

```bash
export ANTHROPIC_CUSTOM_HEADERS="x-hindsight-bank: spruyt-labs"
```

Without the header (and without virtual-key/team metadata) the callback is a safe no-op.

### Virtual-key fallback

To bind a bank to a LiteLLM virtual key instead of a header, set `hindsight_bank` in the key's metadata. Any request using that key then shares the bank without needing the header.

## Configuration (env on the litellm container)

Read once at module init. Defaults shown.

| Env var                       | Default                                                 | Purpose                                  |
| ----------------------------- | ------------------------------------------------------- | ---------------------------------------- |
| `HINDSIGHT_BASE_URL`          | `http://hindsight-api.hindsight.svc.cluster.local:8888` | Hindsight API base                       |
| `HINDSIGHT_TIMEOUT_S`         | `3.0`                                                   | Recall/retain HTTP timeout (fails open)  |
| `HINDSIGHT_RECALL_BUDGET`     | `mid`                                                   | Recall budget: `low` / `mid` / `high`    |
| `HINDSIGHT_MAX_MEMORY_TOKENS` | `4096`                                                  | Cap on injected memory tokens            |
| `HINDSIGHT_INJECT`            | `true`                                                  | Master switch for the recall/inject path |
| `HINDSIGHT_RETAIN`            | `true`                                                  | Master switch for the retain path        |
| `HINDSIGHT_BANK_HEADER`       | `x-hindsight-bank`                                      | Header name used for bank resolution     |

The callback is wired in `values.yaml` under `litellm_settings.callbacks` as `custom_callbacks.hindsight.hindsight_plugin.hindsight_middleware`, resolved via `PYTHONPATH=/app:/app/custom_callbacks` and the configMap subPath mounts.

## Extraction tuning (env on the hindsight-api / worker)

Set in `cluster/apps/hindsight/hindsight/app/values.yaml` under `api.env` and `worker.env` (the worker processes async retain, so both must match). Tuned for Claude Code coding sessions (issue #2270):

| Env var                                      | Value               | Purpose                                                                   |
| -------------------------------------------- | ------------------- | ------------------------------------------------------------------------- |
| `HINDSIGHT_API_RETAIN_STRUCTURED_CHUNK_SIZE` | `8192`              | Keep a whole conversation turn intact (vs splitting at 3000-char default) |
| `HINDSIGHT_API_RETAIN_EXTRACTION_MODE`       | `verbose`           | Richer, context-rich facts (vs `concise` fragmentation)                   |
| `HINDSIGHT_API_RETAIN_MISSION`               | coding-focused      | Steers extraction toward self-contained engineering facts                 |
| `HINDSIGHT_API_RETAIN_LLM_MODEL`             | `claude-haiku-4-5`  | Per-turn extraction — lighter model conserves subscription usage budget   |
| `HINDSIGHT_API_CONSOLIDATION_LLM_MODEL`      | `claude-sonnet-4-6` | Nightly consolidation — stronger model, low volume                        |
| `HINDSIGHT_API_ENABLE_AUTO_CONSOLIDATION`    | `false`             | Consolidation moved off the per-turn path to the nightly CronJob          |

The retain payload **must** be a JSON conversation array for `STRUCTURED_CHUNK_SIZE` to apply — the LiteLLM callback sends the exchange as one such item (see `_conversation_item`).

## Nightly consolidation CronJob

`consolidate-cronjob.yaml` runs `hindsight-consolidate` nightly: it lists banks (`GET /v1/default/banks`) and POSTs `/v1/default/banks/{bank_id}/consolidate` for each. It replaces per-turn auto-consolidation. Network reach is restricted to api:8888 by the `allow-hindsight-consolidate-egress` policy in `network-policies.yaml` plus the matching api ingress rule.

## Verification

```bash
# Plugin importable inside the pod
POD=$(kubectl -n litellm get pod -l app.kubernetes.io/name=litellm -o name | head -1)
kubectl -n litellm exec "$POD" -c litellm -- \
  python -c "import custom_callbacks.hindsight.hindsight_plugin as m; print(type(m.hindsight_middleware))"

# Recall activity (per request)
kubectl -n hindsight logs deploy/hindsight-api | grep -iE "RECALL"

# A recall hit looks like:
#   [RECALL <bank>-...] Complete: 3 facts (70 tok), 0 chunks, 4 entities | ... | 0.15s
```

End-to-end smoke test (master key is referenced, never printed):

```bash
POD=$(kubectl -n litellm get pod -l app.kubernetes.io/name=litellm -o name | head -1)
# 1) RETAIN a fact
kubectl -n litellm exec "$POD" -c litellm -- python - <<'PY'
import os, urllib.request, json
body = {"model": "claude-haiku-4-5", "max_tokens": 64,
        "messages": [{"role": "user", "content": "Remember: the deploy guardian is a teal otter named Bram."}]}
req = urllib.request.Request("http://localhost:4000/v1/messages", data=json.dumps(body).encode(),
    headers={"Authorization": "Bearer " + os.environ["LITELLM_MASTER_KEY"],
             "Content-Type": "application/json", "x-hindsight-bank": "smoke-test"})
urllib.request.urlopen(req, timeout=60).read(); print("retain sent")
PY
sleep 10
# 2) RECALL it (fact is NOT in this prompt)
kubectl -n litellm exec "$POD" -c litellm -- python - <<'PY'
import os, urllib.request, json
body = {"model": "claude-haiku-4-5", "max_tokens": 64,
        "messages": [{"role": "user", "content": "Who is the deploy guardian? Say UNKNOWN if unsure."}]}
req = urllib.request.Request("http://localhost:4000/v1/messages", data=json.dumps(body).encode(),
    headers={"Authorization": "Bearer " + os.environ["LITELLM_MASTER_KEY"],
             "Content-Type": "application/json", "x-hindsight-bank": "smoke-test"})
r = json.load(urllib.request.urlopen(req, timeout=60))
print("".join(b.get("text","") for b in r.get("content", []) if b.get("type") == "text"))
PY
# Expect the answer to name Bram — supplied only by recall injection.
```

## Troubleshooting

| Symptom                       | Check                                                                                                                                                                                                |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No memory injected            | Bank not resolving — confirm the header reaches litellm (`data["proxy_server_request"]["headers"]`) or virtual-key metadata. No bank → intentional skip.                                             |
| Retain silently absent        | `kubectl -n litellm logs "$POD" -c litellm \| grep -i "hindsight retain failed"`. The retain path reads the bank from `litellm_params.proxy_server_request.headers` in the success event.            |
| `422` on retain               | `MemoryItem.context` must be a string. The exchange is sent as ONE item whose `content` is a JSON conversation array (`[{role,content},…]`); `context` is the session label.                         |
| Partial / fragmented memories | Each turn must reach Hindsight as a conversation array so `chunk_text` keeps it whole up to `HINDSIGHT_API_RETAIN_STRUCTURED_CHUNK_SIZE` (8192). A bare string splits at `RETAIN_CHUNK_SIZE` (3000). |
| Slow first token              | Recall is a vector lookup with a 3s fail-open timeout. No per-request LLM call (reflect is intentionally avoided on the hot path).                                                                   |
| Cache-hit regression          | Memory is injected as the **last** system block to preserve the cached prefix. Watch prompt-cache metrics after changes.                                                                             |

Historical logs for deleted/rotated pods: use the `victoria-logs` skill, e.g. `{namespace="litellm"} |~ "hindsight"`.

## Notes & limitations

- **Streaming**: `async_log_success_event` fires after the full response is assembled, so retain works for streamed responses. An aborted stream is not retained (best effort, acceptable).
- The hindsight namespace is locked down with CiliumNetworkPolicies; the litellm → hindsight `api:8888` path is explicitly allowed (`allow-litellm-hindsight-egress` + `allow-hindsight-api-ingress`).
