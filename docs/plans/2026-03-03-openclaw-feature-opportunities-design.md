# OpenClaw v2026.3.2 Feature Opportunities Design

**Issue:** [#592](https://github.com/anthony-spruyt/spruyt-labs/issues/592)
**Date:** 2026-03-03

## Scope

Three feature opportunities identified from the openclaw v2026.3.2 update (PR #584):

1. Native gateway health probes
2. Discord thread lifecycle controls
3. SecretRef expanded credential coverage

## 1. Health Probes — SKIP (upstream bug)

**Decision:** Do not implement. Create a follow-up issue to track.

**Reason:** Open upstream bug [openclaw/openclaw#18446](https://github.com/openclaw/openclaw/issues/18446) confirms that `/health`, `/healthz`, `/ready`, and `/readyz` do not exist as HTTP routes. They hit the Control UI SPA catch-all and return `200 OK` with HTML regardless of gateway health.

The health endpoint only exists as a WebSocket RPC method, which Kubernetes does not support for probes.

**Current state:** TCP socket probes on port 18789. These detect process liveness (port open) and remain the best available option.

**Risk of switching prematurely:** HTTP probes on `/healthz` would always return 200 from the SPA, making probes strictly worse than TCP (never fails, even when gateway is unhealthy).

**Follow-up:** Create GitHub issue to revisit when openclaw ships proper HTTP health endpoints.

## 2. Discord Thread Bindings — IMPLEMENT

**Decision:** Add `threadBindings` configuration to `openclaw.json`.

### Config Change

**File:** `cluster/apps/openclaw/openclaw/app/openclaw.json`

Add to `channels.discord`:

```json
"threadBindings": {
  "enabled": true,
  "idleHours": 72,
  "maxAgeHours": 0
}
```

- `enabled: true` — Activates thread-to-session binding
- `idleHours: 72` — Auto-unfocus threads after 3 days of inactivity
- `maxAgeHours: 0` — No hard maximum age (threads live as long as they're active)

### What This Enables

- Stale Discord threads auto-unfocus after 72 hours of inactivity
- Slash commands unlocked: `/focus`, `/unfocus`, `/agents`, `/session idle`, `/session max-age`
- Thread-scoped session routing for subagents (if `spawnSubagentSessions` is later enabled)

### Files Modified

- `cluster/apps/openclaw/openclaw/app/openclaw.json` — Add `threadBindings` block

### Rollback

Remove the `threadBindings` block from `openclaw.json` and push. Flux auto-reconciles.

## 3. SecretRef Expansion — RESEARCH ISSUE ONLY

**Decision:** Create a research follow-up issue. Do not implement yet.

### Context

v2026.3.2 expanded SecretRef support to 64 credential targets, allowing Kubernetes secrets to be referenced directly in openclaw config instead of using environment variables from SOPS-encrypted secrets.

### Credential Analysis

**Potentially eligible for SecretRef:**

| Key | Type | SecretRef Support | Notes |
|-----|------|-------------------|-------|
| `DISCORD_BOT_TOKEN` | Channel credential | Confirmed (openclaw#32445) | Highest priority candidate |
| `OPENAI_API_KEY` | Model provider | Likely (part of 64-target expansion) | |
| `BRAVE_API_KEY` | Tool credential | Possibly | Web search tool |
| `CONTEXT7_API_KEY` | MCP credential | Possibly | Depends on MCP SecretRef support |
| `HASS_ACCESS_TOKEN` | MCP credential | Possibly | Home Assistant |
| `N8N_TOKEN` | Service credential | Possibly | n8n webhook auth |
| `OPENCLAW_GATEWAY_TOKEN` | Gateway auth | Possibly | Gateway-level credential |

**Not candidates (used outside openclaw config):**

| Key | Reason |
|-----|--------|
| `GH_TOKEN`, `GIT_CODE_TOKEN` | Used by init container scripts |
| `GIT_WORKSPACE_REPO` | Repo URL, not a credential |
| `HASS_BASE_URL`, `N8N_URL` | URLs, not secrets |
| `id_signing`, `.credentials.json`, `mcporter.json` | File-mounted secrets, different pattern |

### Known Upstream Issues

- [openclaw#28359](https://github.com/openclaw/openclaw/issues/28359) — SecretRef keys re-materialized as plaintext in agent config files
- [openclaw#29183](https://github.com/openclaw/openclaw/issues/29183) — SecretRef validation failures for string-only config fields
- [openclaw#30311](https://github.com/openclaw/openclaw/issues/30311) — Exec-based SecretRef auth profile probe failures

**Recommendation:** Wait for #28359 (plaintext re-materialization) to be resolved before migrating any credentials.
