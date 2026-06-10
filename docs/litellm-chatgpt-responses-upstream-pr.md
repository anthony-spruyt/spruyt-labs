# LiteLLM upstream PR draft: ChatGPT Responses routing via Anthropic Messages

## Title

Fix Anthropic Messages pass-through for ChatGPT Responses models

## Summary

Routed Anthropic `/v1/messages` requests that resolve to ChatGPT Responses models can fall out of the Responses API path or open the provider request without real SSE transport. ChatGPT Responses-only models require both the request payload and the HTTP transport to be streaming, even when LiteLLM's caller requested a non-streaming Anthropic response. LiteLLM should force the provider call through
real Responses SSE, then collect the completed response before returning to non-streaming callers.

## Problem

The failing path is:

```text
Anthropic /v1/messages
  -> anthropic experimental pass-through adapter
  -> litellm.aresponses()
  -> responses() in an executor
  -> BaseLLMHTTPHandler.response_api_handler(..., _is_async=True)
  -> AsyncHTTPHandler.post(...)
```

Issues seen on this path:

- ChatGPT is not included in the Anthropic pass-through provider set that is routed to the Responses bridge.
- Routed aliases can lose ChatGPT Responses metadata during model/provider normalization, so the request can miss the provider-specific Responses config.
- `_is_async=True` enters `response_api_handler` first; patching only `async_response_api_handler` misses the live path.
- ChatGPT Responses-only models require real HTTP streaming plus payload `stream: true`; setting only LiteLLM optional params is insufficient.
- Once real SSE is forced, `fake_stream=True` is invalid because the fake iterator reads `.text` from an unread streaming response.
- For non-streaming callers, LiteLLM still needs to consume the SSE iterator and return the final `ResponsesAPIResponse`.

## Proposed upstream fix

1. Add `chatgpt` to the Anthropic Messages pass-through Responses provider set.
2. Preserve Responses mode for ChatGPT models whose config or resolved model indicates `mode: responses`.
3. In `BaseLLMHTTPHandler.response_api_handler`, handle the `_is_async=True` branch before delegating so forced-provider behavior is not bypassed.
4. For ChatGPT Responses-only models, force provider-side real SSE transport and set request JSON `stream: true`.
5. Pass `fake_stream=False` whenever real provider SSE transport is forced.
6. If the original LiteLLM caller did not request streaming, consume the Responses streaming iterator and return the completed response object.
7. Add regression tests covering Anthropic Messages aliases routed to ChatGPT Responses models, direct ChatGPT Responses calls, streaming callers, and non-streaming callers.

## Local proof in spruyt-labs

The local carry patch lives in `cluster/apps/litellm/litellm/app/plugins/chatgpt/litellm_patch.py` and is loaded by the existing ChatGPT callback plugin. It avoids replacing `/app/litellm/main.py`, so LiteLLM image updates are lower-friction while this waits for upstream.

Validated locally:

- `task test:litellm-middleware` passes.
- Kustomize render includes `litellm_patch.py` mounted under `/app/custom_callbacks/chatgpt/`.
- Kustomize render no longer mounts a full `/app/litellm/main.py` override.

## Notes for an upstream implementation

The local patch is deliberately scoped to configured aliases for `gpt-5.5` and `gpt-5.4-mini`. Upstream should not hardcode those names. Prefer provider/config-level detection of ChatGPT Responses models and provider capabilities.
