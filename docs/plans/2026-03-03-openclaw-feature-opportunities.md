# OpenClaw v2026.3.2 Feature Opportunities Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement Discord thread bindings, create follow-up issues for health probes and SecretRef research, and close the parent tracking issue.

**Architecture:** Config-only change to `openclaw.json` for thread bindings. Two GitHub issues created for deferred work. All changes reconciled via Flux.

**Tech Stack:** OpenClaw config (JSON), GitHub CLI, Flux GitOps

---

### Task 1: Create follow-up issue for health probes

**Context:** openclaw's `/healthz` endpoint doesn't exist as an HTTP route (upstream bug [openclaw#18446](https://github.com/openclaw/openclaw/issues/18446)). TCP probes remain the best option until this is fixed upstream.

**Step 1: Create the GitHub issue**

```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "feat(openclaw): switch to native HTTP health probes when upstream fix lands" \
  --label "enhancement" \
  --label "blocked" \
  --body "$(cat <<'EOF'
## Summary

Switch openclaw gateway health probes from TCP socket to native HTTP endpoints (`/healthz` for liveness, `/ready` for readiness) once upstream [openclaw/openclaw#18446](https://github.com/openclaw/openclaw/issues/18446) is resolved.

## Motivation

HTTP health probes provide application-level health signals (e.g., gateway overloaded, dependencies down) rather than just confirming the port is open. However, as of v2026.3.2, `/healthz` and `/health` hit the Control UI SPA catch-all and always return `200 OK` with HTML — making them useless for K8s probes.

**Current state:** TCP socket probes on port 18789 in `cluster/apps/openclaw/openclaw/app/values.yaml`.

**Upstream bug:** [openclaw/openclaw#18446](https://github.com/openclaw/openclaw/issues/18446) — no HTTP health route exists; health is only available via WebSocket RPC.

## Acceptance Criteria

- [ ] Upstream openclaw/openclaw#18446 is resolved (HTTP `/healthz` returns JSON health payload)
- [ ] Liveness probe switched from TCP to HTTP GET `/healthz` on port 18789
- [ ] Readiness probe switched from TCP to HTTP GET `/ready` on port 18789
- [ ] Startup probe switched from TCP to HTTP GET `/healthz` on port 18789
- [ ] Probe timings reviewed for HTTP overhead (slightly relaxed periods recommended)
- [ ] Verified via `kubectl describe pod` that probes report healthy after deploy

## Affected Area

Apps (cluster/apps/)

## Implementation Notes

File to modify: `cluster/apps/openclaw/openclaw/app/values.yaml`

Current TCP probe config (main container):
```yaml
probes:
  liveness:
    type: TCP
    spec:
      tcpSocket:
        port: 18789
```

Target HTTP probe config:
```yaml
probes:
  liveness:
    enabled: true
    type: HTTP
    spec:
      httpGet:
        path: /healthz
        port: 18789
      initialDelaySeconds: 30
      periodSeconds: 30
      timeoutSeconds: 5
      failureThreshold: 3
```

## Related Issues/PRs

- #592 (parent tracking issue)
- Upstream: openclaw/openclaw#18446
EOF
)"
```

**Step 2: Record the issue number**

Note the returned issue number for later reference in the parent issue.

---

### Task 2: Create follow-up issue for SecretRef research

**Context:** v2026.3.2 expanded SecretRef to 64 credential targets. Research which of the 12 openclaw secrets could migrate, but don't implement yet due to upstream bugs.

**Step 1: Create the GitHub issue**

```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "chore(openclaw): research SecretRef migration for SOPS-encrypted credentials" \
  --label "chore" \
  --body "$(cat <<'EOF'
## Summary

Research which openclaw credentials can migrate from SOPS-encrypted environment variables to native SecretRef references, reducing SOPS complexity.

## Motivation

OpenClaw v2026.3.2 expanded SecretRef support to 64 credential targets. This could simplify secret management by referencing K8s secrets directly in openclaw config instead of injecting via environment variables from SOPS-encrypted secrets.

## Chore Type

Configuration change

## Affected Area

Apps (cluster/apps/)

## Credential Analysis

**Potentially eligible for SecretRef:**

| Key | Type | SecretRef Support | Notes |
|-----|------|-------------------|-------|
| `DISCORD_BOT_TOKEN` | Channel credential | Confirmed (openclaw#32445) | Highest priority |
| `OPENAI_API_KEY` | Model provider | Likely (64-target expansion) | |
| `BRAVE_API_KEY` | Tool credential | Possibly | Web search |
| `CONTEXT7_API_KEY` | MCP credential | Possibly | MCP SecretRef support TBD |
| `HASS_ACCESS_TOKEN` | MCP credential | Possibly | Home Assistant |
| `N8N_TOKEN` | Service credential | Possibly | n8n webhook auth |
| `OPENCLAW_GATEWAY_TOKEN` | Gateway auth | Possibly | Gateway-level |

**Not candidates (used outside openclaw config):**

| Key | Reason |
|-----|--------|
| `GH_TOKEN`, `GIT_CODE_TOKEN` | Used by init container scripts |
| `GIT_WORKSPACE_REPO` | Repo URL, not a credential |
| `HASS_BASE_URL`, `N8N_URL` | URLs, not secrets |
| `id_signing`, `.credentials.json`, `mcporter.json` | File-mounted secrets, different pattern |

## Task Checklist

- [ ] Wait for upstream openclaw#28359 (SecretRef plaintext re-materialization bug) to be resolved
- [ ] Verify which of the 7 candidate credentials have confirmed SecretRef support
- [ ] Test SecretRef config syntax with `DISCORD_BOT_TOKEN` as pilot
- [ ] Document migration steps for each confirmed credential
- [ ] Implement migration in a separate PR

## Risks/Considerations

**Upstream bugs to watch:**
- [openclaw#28359](https://github.com/openclaw/openclaw/issues/28359) — SecretRef keys re-materialized as plaintext in agent config (BLOCKER)
- [openclaw#29183](https://github.com/openclaw/openclaw/issues/29183) — SecretRef validation failures for string-only fields
- [openclaw#30311](https://github.com/openclaw/openclaw/issues/30311) — Exec-based SecretRef auth probe failures

**Recommendation:** Do NOT implement until #28359 is resolved.

## Related Issues/PRs

- #592 (parent tracking issue)
- Upstream: openclaw/openclaw#32445, openclaw/openclaw#28306
EOF
)"
```

**Step 2: Record the issue number**

Note the returned issue number for later reference in the parent issue.

---

### Task 3: Add Discord thread bindings to openclaw.json

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/openclaw.json:180-202` (inside `channels.discord`)

**Step 1: Add the threadBindings config**

In `cluster/apps/openclaw/openclaw/app/openclaw.json`, add a `threadBindings` block inside the `channels.discord` object, after the `guilds` block (before the closing `}` of the `discord` object).

The `channels.discord` section should end up as:

```json
"channels": {
  "discord": {
    "enabled": true,
    "streamMode": "off",
    "groupPolicy": "allowlist",
    "dmPolicy": "allowlist",
    "allowFrom": ["249242152318664709"],
    "dm": {
      "enabled": true
    },
    "guilds": {
      "257529418187145216": {
        "requireMention": true,
        "users": ["249242152318664709"],
        "channels": {
          "1473506635656990862": {
            "allow": true,
            "requireMention": false
          }
        }
      }
    },
    "threadBindings": {
      "enabled": true,
      "idleHours": 72,
      "maxAgeHours": 0
    }
  }
}
```

Use the Edit tool to add a comma after the closing `}` of the `guilds` block, then add the `threadBindings` block.

**Step 2: Validate JSON syntax**

```bash
python3 -c "import json; json.load(open('cluster/apps/openclaw/openclaw/app/openclaw.json'))" && echo "JSON valid" || echo "JSON INVALID"
```

Expected: `JSON valid`

**Step 3: Validate against schema**

```bash
python3 -c "
import json
with open('cluster/apps/openclaw/openclaw/app/openclaw.json') as f:
    config = json.load(f)
tb = config['channels']['discord']['threadBindings']
assert tb['enabled'] == True, 'enabled should be True'
assert tb['idleHours'] == 72, 'idleHours should be 72'
assert tb['maxAgeHours'] == 0, 'maxAgeHours should be 0'
print('threadBindings config verified')
"
```

Expected: `threadBindings config verified`

---

### Task 4: Run qa-validator

**Context:** Files under `cluster/` were modified. Run qa-validator before committing.

**Step 1: Run qa-validator agent**

Use the qa-validator agent to validate the changes.

Expected: APPROVED (JSON config change, no schema-breaking modifications)

---

### Task 5: Commit and create PR

**Step 1: Commit the config change**

```bash
git add cluster/apps/openclaw/openclaw/app/openclaw.json
git commit -m "$(cat <<'EOF'
feat(openclaw): add Discord thread bindings with 3-day idle TTL

Enable threadBindings in openclaw Discord config:
- enabled: true (activates thread-to-session binding)
- idleHours: 72 (auto-unfocus after 3 days of inactivity)
- maxAgeHours: 0 (no hard max age)

Unlocks /focus, /unfocus, /session idle, /session max-age
slash commands in Discord.

Ref #592

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

**Step 2: Create PR**

```bash
gh pr create --title "feat(openclaw): add Discord thread bindings with 3-day idle TTL" --body "$(cat <<'EOF'
## Summary
- Enable Discord thread bindings in openclaw config with 72-hour idle TTL
- Stale threads auto-unfocus after 3 days of inactivity
- Unlocks `/focus`, `/unfocus`, `/session idle`, `/session max-age` Discord commands

## Linked Issue
Ref #592

## Changes
- `cluster/apps/openclaw/openclaw/app/openclaw.json`: Add `threadBindings` block to `channels.discord`

## Follow-Up Issues Created
- Health probes: blocked on upstream openclaw#18446 (tracked in new issue)
- SecretRef research: deferred pending upstream openclaw#28359 (tracked in new issue)

## Testing
- [ ] JSON syntax validated
- [ ] threadBindings values verified (enabled=true, idleHours=72, maxAgeHours=0)
- [ ] qa-validator passed
- [ ] After merge: Flux reconciles, pod restarts with new config
- [ ] After merge: Verify `/focus` command available in Discord

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

### Task 6: Post-merge validation

**Prerequisite:** User has pushed/merged the PR to main.

**Step 1: Run cluster-validator agent**

Use the cluster-validator agent to verify the deployment reconciled correctly.

**Step 2: Comment on parent issue with results**

```bash
gh issue comment 592 --repo anthony-spruyt/spruyt-labs --body "$(cat <<'EOF'
## Feature Opportunities Resolution

### 1. Health Probes — Deferred
Created follow-up issue #<HEALTH_ISSUE>. Blocked on upstream openclaw/openclaw#18446 (no HTTP health route exists).

### 2. Discord Thread Bindings — Implemented
PR #<PR_NUMBER> adds `threadBindings` to Discord config:
- `enabled: true`
- `idleHours: 72` (3-day idle TTL)
- `maxAgeHours: 0` (no hard limit)

### 3. SecretRef Research — Deferred
Created follow-up issue #<SECRETREF_ISSUE>. Blocked on upstream openclaw/openclaw#28359 (plaintext re-materialization bug).
EOF
)"
```

Replace `<HEALTH_ISSUE>`, `<PR_NUMBER>`, and `<SECRETREF_ISSUE>` with actual numbers from Tasks 1, 2, and 5.
