# Renovate PR Automation via n8n

## Status

Draft - Pending review

## Problem

Renovate dependency update PRs require manual intervention: a human triggers the `renovate-pr-processor` skill in Claude Code, reviews the analysis, confirms merges one by one, and monitors post-merge validation. This is slow, error-prone, and doesn't scale across multiple repositories.

## Goal

Replace the human-in-the-loop `renovate-pr-processor` skill and `renovate-pr-analyzer` agent with webhook-triggered n8n workflows that automatically triage, merge, validate, and revert Renovate PRs. Design the merge infrastructure generically so non-Renovate PRs can use it later.

## Components Summary

| Component                   | Purpose                                                                       |
| --------------------------- | ----------------------------------------------------------------------------- |
| Kyverno init container      | Clone repo into `/workspace` when `CLONE_URL` env var present                 |
| Workflow 1: Triage          | Analyze PR, comment verdict, route by verdict (SAFE/BREAKING/BLOCKED/UNKNOWN) |
| Workflow 2: Queue Processor | Valkey-locked sequential merge, validate, revert PR on failure                |
| Workflow 3: Fix Breaking    | Write-tier agent addresses breaking changes, pushes fix to PR branch          |
| Merge Queue (Valkey queue)  | Generic PR queue, source-agnostic, priority-ordered                           |

## Architecture Overview

```text
GitHub Webhook
|  |
     v
[Existing Webhook Workflow] ── routes pull_request events
|  |
     v
[Workflow 1: Triage] ── read-tier agent analyzes PR
     |                    posts comment with verdict
|  |
     +── [SAFE] ────────> [Merge Queue] (Valkey sorted set)
|  |
     |                         v
     |                    [Workflow 2: Queue Processor] ── Valkey lock
     |                         dequeues one at a time
     |                         write-tier agent: merge -> validate -> revert PR if fail
     |                         loops until queue empty
|  |
     +── [BREAKING] ──> [Workflow 3: Fix Breaking Changes]
     |                    write-tier agent fixes config
     |                    pushes to PR branch
     |                    → re-triggers triage via synchronize event
     |                    max 2 retries → escalate to BLOCKED
|  |
     +── [BLOCKED] ───> Label PR, Discord notify, wait for upstream
|  |
     +── [UNKNOWN] ───> Discord notify, human review
|  |
     v
[Discord #skynet] ── notifications for all outcomes
```

## Components

### 1. Repo Clone via Kyverno Init Container

Inject a git-clone init container into agent pods when `CLONE_URL` env var is present. No changes to the n8n node or container image needed.

**How it works:**
1. n8n credential `envVars` JSON includes `CLONE_URL` (and optionally `CLONE_BRANCH`)
2. Node builds pod spec with env vars on main container, `workingDir: /workspace`
3. Kyverno ClusterPolicy matches pods with `managed-by: n8n-claude-code` label
4. Precondition: `CLONE_URL` env var exists on main container
5. Kyverno injects:
   - `emptyDir` volume named `workspace`
   - Init container that clones repo into `/workspace`
   - Volume mount on both init container and main container at `/workspace`
6. Init container completes → main container starts with repo at CWD
7. Claude CLI boots → CLAUDE.md + `.claude/` (agents, skills, hooks) load naturally

**Kyverno rule (added to existing `inject-claude-agent-config` policy):**

```yaml
- name: inject-repo-clone
  match:
    any:
      - resources:
          kinds: ["Pod"]
          namespaces:
            - claude-agents-write
            - claude-agents-read
          selector:
            matchLabels:
              managed-by: n8n-claude-code
  preconditions:
    all:
      - key: "{{ request.object.spec.containers[0].env[?name=='CLONE_URL'].value | [0] }}"
        operator: NotEquals
        value: ""
  mutate:
    patchStrategicMerge:
      spec:
        volumes:
          - name: workspace
            emptyDir: {}
        initContainers:
          - name: git-clone
            image: alpine/git:2.47.2
            command: ["sh", "-c"]
            args:
              - |
                git clone --depth 1 ${CLONE_BRANCH:+-b "$CLONE_BRANCH"} "$CLONE_URL" /workspace
            env:
              - name: CLONE_URL
                value: "{{ request.object.spec.containers[0].env[?name=='CLONE_URL'].value | [0] }}"
              - name: CLONE_BRANCH
                value: "{{ request.object.spec.containers[0].env[?name=='CLONE_BRANCH'].value | [0] }}"
              - name: GIT_SSH_COMMAND
                value: "ssh -i /etc/git-ssh/id_ed25519 -o StrictHostKeyChecking=no"
              - name: GIT_CONFIG_GLOBAL
                value: /etc/gitconfig/gitconfig
            volumeMounts:
              - name: workspace
                mountPath: /workspace
              - name: github-ssh-key
                mountPath: /etc/git-ssh
                readOnly: true
              - name: github-gitconfig
                mountPath: /etc/gitconfig
                readOnly: true
        containers:
          - (name): "?*"
            volumeMounts:
              - name: workspace
                mountPath: /workspace
```

**Behavior:**
- `CLONE_URL` set in credential env vars: init container clones repo, CLI starts with full context
- `CLONE_URL` not set: precondition fails, no init container injected, existing workflows unaffected
- `CLONE_BRANCH` optional: defaults to repo default branch if omitted

**Verified:** Main container `workingDir` defaults to `/workspace` (from `credentials.defaultWorkingDir || "/workspace"` in `podSpecBuilder.ts` line 117). Init container populates same path via shared emptyDir. No conflict.

**Dependencies:**
- SSH key and git config already injected by existing Kyverno rules (volumes `ssh-key` and `gitconfig`)
- Init container mounts the same SSH/git secrets for authenticated clone

**Credential configuration:** One n8n credential per repo. Credential `envVars` JSON:
```json
{"CLONE_URL": "git@github.com:anthony-spruyt/spruyt-labs.git"}
```
Optionally with branch: `{"CLONE_URL": "...", "CLONE_BRANCH": "main"}`

### 2. Merge Queue (Valkey Sorted Set + Hashes)

Generic queue for PRs approved for merge. Not Renovate-specific. Stored in Valkey (not n8n Valkey queues) for atomic operations and direct access from n8n Redis nodes.

**Key prefix convention:** All n8n-to-Valkey keys MUST use `n8n:` prefix. The Valkey ACL for the
n8n user is `~n8n:*`, blocking access to any key without this prefix. Future Valkey-based features
must follow this convention.

**Queue structure:**

- **Sorted set** `n8n:merge-queue` — ordered queue. Score = `priority * 1e12 + unix_ms`. Member = item key (e.g., `pr:anthony-spruyt/spruyt-labs:123`).
- **Hash per item** `n8n:merge-queue:<member>` — metadata for each queued PR.

**Hash fields:**

| Field          | Purpose                                                      |
| -------------- | ------------------------------------------------------------ |
| `pr_number`    | PR number                                                    |
| `repo`         | `owner/repo` format                                          |
| `source`       | Origin: `renovate`, `human`, `dependabot`, etc.              |
| `priority`     | 0=critical, 1=digest/date/patch, 2=minor, 3=major, 4=other   |
| `status`       | `pending` / `processing` / `done` / `failed` / `reverted`    |
| `enqueued_at`  | ISO timestamp                                                |
| `verdict_json` | Triage output (structured analysis summary)                  |
| `session_id`   | Claude session ID for resume if needed                       |
| `pr_url`       | Full PR URL for reference                                    |
| `head_branch`  | PR source branch                                             |

**Operations:**

- **Enqueue:** `ZADD n8n:merge-queue <score> <member>` + `HSET n8n:merge-queue:<member> ...fields`
- **Dequeue:** `ZPOPMIN n8n:merge-queue 1` (atomic — no race condition)
- **Update status:** `HSET n8n:merge-queue:<member> status <new_status>`
- **Check queue size:** `ZCARD n8n:merge-queue`

**Ordering:** Lower score = higher priority = dequeued first. Within same priority, earlier `enqueued_at` wins (lower unix_ms).

### 3. Workflow 1: Triage Renovate PR

**Replaces:** `renovate-pr-analyzer` agent + triage portion of `renovate-pr-processor` skill.

**Workflow ID:** `WZFm9M1CRhXkPlW1` (existing, currently WIP)

**Trigger:** Called by existing webhook workflow (`e9nTmnZGu8Li29iW`) on `pull_request` events: `opened`, `synchronize`, `ready_for_review`.

**Input:** `pull_request` and `repository` objects from GitHub webhook payload.

#### Triage Flow

```text
Receive PR data + patch from webhook workflow
|  |
     v
Claude Code (read-tier ephemeral pod)
  - Settings: renovate.json via --settings flag in additionalArgs (GitHub MCP + context7 + bravesearch)
  - Model: sonnet (cost-effective for analysis)
  - Prompt: analyze changelog, breaking changes, config impact
  - Output: structured JSON via jsonSchema option
|  |
     v
Post comment on PR with triage summary
|  |
     v
[If SAFE] ── Insert row into merge-queue Valkey queue
          |   (status=pending, priority based on semver level)
|  |
          v
          Trigger Queue Processor workflow

[If BREAKING] ── Spawn write-tier agent to fix (Workflow 3)
              |   Agent pushes fix commit to PR branch
              |   PR `synchronize` event re-triggers triage
              |   Max 2 retry attempts before escalating to BLOCKED
              |   Discord notification: "Attempting to fix breaking changes"

[If BLOCKED] ── Label PR with `blocked`
             |   Discord notification to #skynet
             |   No enqueue, wait for upstream fix

[If UNKNOWN] ── Discord notification to #skynet
                No enqueue, human review needed
```

#### Agent Prompt (Triage)

The read-tier agent receives:
- PR metadata (title, body, labels, author)
- PR patch/diff
- Repository context (CLAUDE.md, .claude/ loaded from CWD)

Agent tasks:
1. Identify dependency being updated (name, old version, new version)
2. Classify update level: patch / minor / major / digest / date / other
3. Fetch upstream changelog and release notes
4. Search upstream GitHub for version-specific issues/bugs
5. Read actual deployed config files (values.yaml, release.yaml, ks.yaml)
6. Cross-reference breaking changes against deployed configuration
7. Assess impact: NO_IMPACT / LOW_IMPACT / HIGH_IMPACT / UNKNOWN_IMPACT

#### Structured Output Schema

```json
{
  "type": "object",
  "required": ["verdict", "summary", "dependency", "semverLevel", "breakingChanges", "features"],
  "properties": {
    "verdict": {
      "type": "string",
      "enum": ["SAFE", "BREAKING", "BLOCKED", "UNKNOWN"]
    },
    "summary": {
      "type": "string",
      "description": "1-3 sentence summary of analysis"
    },
    "dependency": {
      "type": "object",
      "properties": {
        "name": { "type": "string" },
        "oldVersion": { "type": "string" },
        "newVersion": { "type": "string" },
        "type": { "type": "string", "enum": ["helm", "image", "taskfile", "other"] }
      }
    },
    "semverLevel": {
      "type": "string",
      "enum": ["patch", "minor", "major", "digest", "date", "other"]
    },
    "breakingChanges": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "description": { "type": "string" },
          "impact": { "type": "string", "enum": ["NO_IMPACT", "LOW_IMPACT", "HIGH_IMPACT", "UNKNOWN_IMPACT"] },
          "reason": { "type": "string" }
        }
      }
    },
    "features": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "description": { "type": "string" },
          "relevance": { "type": "string", "enum": ["HIGH", "MEDIUM", "LOW"] }
        }
      }
    }
  }
}
```

#### Verdict Rules

- **SAFE:** No breaking changes, or all breaking changes assessed as NO_IMPACT/LOW_IMPACT
- **BREAKING:** Breaking changes exist but can be addressed by updating our configuration, values, or code (e.g., renamed Helm key, changed API, deprecated field)
- **BLOCKED:** Upstream critical bug, known regression, or issue that cannot be fixed on our side — must wait for a newer release
- **UNKNOWN:** Insufficient evidence to assess (changelog missing, upstream issues unclear)

### 4. Workflow 3: Fix Breaking Changes

**New workflow.** Spawns a write-tier agent to address breaking changes identified by triage.

**Trigger:** Called by Workflow 1 when verdict is BREAKING.

**Input:** PR data, breaking changes list from triage verdict, repository info.

#### Fix Flow

```text
Receive PR data + breaking changes from triage
|  |
     v
Claude Code (write-tier ephemeral pod)
  - Settings: merge-agent.json via --settings flag in additionalArgs (needs GitHub MCP + kubectl)
  - Model: opus (complex refactoring)
  - Prompt: checkout PR branch, address breaking changes, commit + push fix
  - Receives: breaking change descriptions + impact + affected config files
|  |
     v
[Agent pushes fix commit to PR branch]
|  |
     v
GitHub fires `synchronize` event → webhook workflow → triage re-runs automatically
```

**Retry tracking:** Triage workflow checks PR comments/labels for previous BREAKING verdicts. If 2+ BREAKING verdicts already exist for same PR, escalate to BLOCKED instead of retrying.

**Agent tasks:**
1. Clone repo, checkout PR branch
2. For each breaking change: update affected config (values.yaml, release.yaml, etc.)
3. Run local validation (kustomize build, yaml lint)
4. Commit with message: `fix: address breaking changes for <dep> <version>`
5. Push to PR branch

### 5. Workflow 2: Queue Processor

**New workflow.** Processes the merge queue sequentially with Valkey distributed lock.

**Triggers:**
- Direct call from Workflow 1 after enqueue (fast path)
- Cron every 10 minutes (safety net for missed triggers, crash recovery)

#### Valkey Lock Pattern

```text
Start
|  |
  v
SET n8n:lock:merge-queue processing NX EX 1800   (atomic: only sets if not exists)
|  |
  v
[Lock acquired?]
|  |
  NO        YES
|  |
  Exit      v
         Process Loop:
|  |
            v
         ZPOPMIN n8n:merge-queue 1   (atomic dequeue, lowest score first)
|  |
            v
         [Item popped?]
|  |
            NO        YES
|  |
            v         v
         DELETE    HSET n8n:merge-queue:<key> status processing
         lock     |
         Exit     v
               Spawn write-tier agent (persistent pod)
|  |
                  v
               Merge + Validate + Revert-if-needed
|  |
                  v
               HSET n8n:merge-queue:<key> status (done/failed/reverted)
|  |
                  v
               Discord notification
|  |
                  v
               Loop back to "Query Valkey queue"
```

**TTL (1800s / 30min):** Dead-man's switch. If processor crashes, lock auto-expires. Cron picks up remaining items on next tick.

**Re-check loop:** After processing all pending items, processor checks the queue again before unlocking. Items enqueued during processing get handled immediately. Only exits when queue is empty.

#### Merge + Validate + Revert Agent

The write-tier agent handles the full lifecycle for one PR:

1. **Squash merge** the PR via GitHub API
2. **Check** if merged files include anything under `cluster/`
3. **If cluster changed:** Run validation (agent reads CLAUDE.md, uses appropriate validation strategy — for this repo, cluster-validator subagent)
4. **If validation passes:** Update queue status=done. If linked GitHub issue exists, close it.
5. **If validation fails:** `git revert <merge-commit> && git push origin main` (no branch protection — trunk-based dev). Update queue status=reverted. Reopen original PR.

**Agent configuration:**
- Connection mode: `k8sPersistent` (stays alive for multi-step work)
- Settings: `merge-agent.json` via `--settings` flag in `additionalArgs` (needs GitHub MCP + kubectl + victoriametrics)
- Model: `opus` (complex multi-step reasoning: merge decisions, validation interpretation, revert logic)
- Max budget: configurable per execution to prevent runaway costs

### 6. Settings Profiles

Settings profiles are mounted into agent pods at `/etc/claude/settings/` by the existing Kyverno
`inject-claude-agent-config` policy.

**Prerequisite:** Most profiles are currently commented out in
`cluster/apps/claude-agents-shared/base/kustomization.yaml` and must be uncommented.
`merge-agent.json` must be created.

**Usage:** The n8n Claude Code node does not have a `settingsProfile` parameter.
Profiles are passed via the `additionalArgs` option: `--settings /etc/claude/settings/<profile>.json`.

#### renovate.json (Triage — read-only analysis)

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "deniedMcpServers": [
    { "serverName": "kubectl" },
    { "serverName": "victoriametrics" },
    { "serverName": "sre" },
    { "serverName": "discord" },
    { "serverName": "homeassistant" }
  ]
}
```

Allows: GitHub MCP, context7, bravesearch.

#### merge-agent.json (Queue Processor — write operations)

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "deniedMcpServers": [
    { "serverName": "homeassistant" }
  ]
}
```

Allows: GitHub MCP, kubectl, victoriametrics, sre, context7, bravesearch, discord.

### 7. Notifications

All outcomes post to Discord #skynet channel (ID: `1473506635656990862`, server: `257529418187145216`).

| Event                             | Message                                                                           |
| --------------------------------- | --------------------------------------------------------------------------------- |
| PR triaged SAFE                   | `:white_check_mark: PR #X (dep vOLD -> vNEW) triaged SAFE — enqueued for merge`   |
| PR triaged BREAKING               | `:wrench: PR #X (dep vOLD -> vNEW) triaged BREAKING — attempting fix`             |
| PR triaged BLOCKED                | `:no_entry: PR #X (dep vOLD -> vNEW) triaged BLOCKED — upstream issue, waiting`   |
| PR triaged UNKNOWN                | `:question: PR #X (dep vOLD -> vNEW) triaged UNKNOWN — insufficient evidence`     |
| Breaking fix failed (max retries) | `:no_entry: PR #X escalated to BLOCKED after 2 fix attempts`                      |
| Merge + validation success        | `:rocket: PR #X merged and validated successfully`                                |
| Validation failed + reverted      | `:rotating_light: PR #X merged but validation failed -- revert PR created: #Y`    |
| Queue processor error             | `:x: Queue processor error: <error summary>`                                      |

### 8. Existing Webhook Workflow Changes

Workflow `e9nTmnZGu8Li29iW` already routes `pull_request` events for Renovate PRs to the triage sub-workflow. Minimal changes needed:

- Remove WIP gate (always-false IF node) in Renovate PR agent workflow
- Ensure PR patch is passed to triage workflow
- Add `workflow_run` event handling if needed for CI status checks (future)

## Sequential Merge Constraint

PRs merge one at a time. Never batch. Reasons:
- Single revert target if validation fails
- Reduced noise in cluster reconciliation
- Clear cause-effect attribution for failures
- Valkey lock + loop pattern enforces this naturally

## Replaces

| Current                                            | Replacement                                          |
| -------------------------------------------------- | ---------------------------------------------------- |
| `renovate-pr-processor` skill (`.claude/skills/`)  | Workflow 1 (triage) + Workflow 2 (queue processor)   |
| `renovate-pr-analyzer` agent (`.claude/agents/`)   | Triage agent prompt in Workflow 1                    |
| Manual human trigger                               | GitHub webhook trigger (automatic)                   |
| Human merge confirmation                           | Auto-merge for SAFE verdicts                         |

The existing skill and agent remain functional as a fallback during rollout but are deprecated once the n8n automation is stable.

## Future Extensions

- **Non-Renovate PRs:** Any triage workflow (code review, security scan) can enqueue to the same merge queue. Queue processor is source-agnostic.
- **Multi-repo:** Different credentials per repo (each with its own `CLONE_URL`). Same workflows, different credential selection based on `repository` field in webhook payload.
- **Approval workflows:** RISKY PRs could enqueue with a `needs_approval` status. Human approves via Discord reaction or GitHub label → status changes to `pending` → processor picks it up.
- **Priority override:** Critical security patches could be enqueued with priority=0, jumping ahead of regular updates.

## Risks and Mitigations

| Risk                                | Mitigation                                                                                    |
| ----------------------------------- | --------------------------------------------------------------------------------------------- |
| Triage misclassifies RISKY as SAFE  | Post-merge validation catches it; auto-revert PR created                                      |
| Git revert push fails               | Discord alert for human follow-up; lock TTL expires allowing retry                            |
| Queue processor crashes mid-merge   | Valkey TTL expires lock; cron restarts processing; partial state visible in Valkey queue      |
| n8n downtime misses webhook         | GitHub webhook retry (redelivery); cron catches queued items on recovery                      |
| Agent cost runaway                  | `maxBudgetUsd` per execution; sonnet for triage (cheap), opus only for merge                  |
| Concurrent queue access             | Valkey lock prevents double processing; GET→SET race window negligible at trigger frequency   |

## Implementation Order

1. Add Kyverno init container rule for repo clone (inject-claude-agent-config policy)
2. Create n8n Valkey queue for merge queue
3. Create `merge-agent.json` settings profile
4. Build Workflow 2 (queue processor) with Valkey lock
5. Build Workflow 3 (fix breaking changes)
6. Complete Workflow 1 (triage) — remove WIP gate, add structured output, enqueue logic, BREAKING/BLOCKED routing
7. Wire up webhook workflow to updated triage workflow
8. Test with a real Renovate patch PR
9. Test BREAKING flow with a known breaking change
10. Deprecate `renovate-pr-processor` skill and `renovate-pr-analyzer` agent
