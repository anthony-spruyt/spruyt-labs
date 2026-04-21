# Renovate PR Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace manual Renovate PR processing with webhook-triggered n8n workflows that triage, merge, validate, and revert PRs automatically.

**Architecture:** GitHub webhooks trigger n8n triage workflow (read-tier Claude agent analyzes PR). SAFE PRs enqueue to a data table. Queue processor workflow (Valkey-locked) dequeues and merges sequentially with post-merge validation. BREAKING PRs get a write-tier fix agent. All notifications go to Discord #skynet.

**Tech Stack:** n8n workflows, n8n-nodes-claude-code-cli custom node, Kyverno ClusterPolicy, Valkey/Redis, n8n data tables, GitHub API.

**Spec:** `docs/superpowers/specs/2026-04-21-renovate-pr-automation-design.md`

---

## File Map

| Action | Path | Purpose |
| ------ | ---- | ------- |
| Modify | `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml` | Add repo-clone init container rule |
| Modify | `cluster/apps/claude-agents-shared/base/kustomization.yaml` | Uncomment renovate.json, add merge-agent.json |
| Modify | `cluster/apps/claude-agents-shared/base/settings/renovate.json` | Already exists, verify content |
| Create | `cluster/apps/claude-agents-shared/base/settings/merge-agent.json` | New settings profile for merge agent |
| Modify (n8n) | Workflow `WZFm9M1CRhXkPlW1` "Renovate PR agent" | Complete triage workflow |
| Create (n8n) | New workflow "Merge Queue Processor" | Queue processor with Valkey lock |
| Create (n8n) | New workflow "Fix Breaking Changes" | Write-tier breaking change fixer |
| Modify (n8n) | Workflow `e9nTmnZGu8Li29iW` "GitHub webhooks" | Remove WIP gate connection |
| Create (Valkey) | Sorted set `n8n:merge-queue` + hashes | PR merge queue (no n8n data table) |
| Create (n8n) | n8n credential "Claude write-tier spruyt-labs" | Write-tier cred with CLONE_URL |
| Create (n8n) | n8n credential "Claude read-tier spruyt-labs" | Read-tier cred with CLONE_URL |

---

## Task 1: Create merge-agent.json Settings Profile

**Files:**
- Create: `cluster/apps/claude-agents-shared/base/settings/merge-agent.json`
- Modify: `cluster/apps/claude-agents-shared/base/kustomization.yaml`

- [ ] **Step 1: Create the merge-agent settings profile**

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "deniedMcpServers": [
    { "serverName": "homeassistant" }
  ]
}
```

Write to `cluster/apps/claude-agents-shared/base/settings/merge-agent.json`.

- [ ] **Step 2: Enable settings profiles in kustomization.yaml**

In `cluster/apps/claude-agents-shared/base/kustomization.yaml`, uncomment the commented-out profiles and add the new one. The `configMapGenerator` section should become:

```yaml
configMapGenerator:
  - name: claude-settings-profiles
    files:
      - settings/admin.json
      - settings/dev.json
      - settings/pr.json
      - settings/renovate.json
      - settings/sre.json
      - settings/merge-agent.json
```

- [ ] **Step 3: Verify renovate.json content matches spec**

Read `cluster/apps/claude-agents-shared/base/settings/renovate.json` and confirm it denies kubectl, victoriametrics, sre, discord, homeassistant. It currently does -- no change needed.

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/claude-agents-shared/base/settings/merge-agent.json \
        cluster/apps/claude-agents-shared/base/kustomization.yaml
git commit -m "feat(agents): add merge-agent settings profile and enable all profiles"
```

---

## Task 2: Add Kyverno Init Container for Repo Clone

**Files:**
- Modify: `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml`

**Critical context:** The existing policy mounts SSH key at `/etc/git-ssh` (not `/root/.ssh`) and gitconfig at `/etc/gitconfig` (not `/root/.gitconfig`). The init container must use these same paths. The git SSH command must be configured via `GIT_SSH_COMMAND` env var since the key is not at the default SSH path.

- [ ] **Step 1: Add the inject-repo-clone rule**

Add a third rule to the existing ClusterPolicy in `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml`. Insert after the `inject-read-config` rule (after line 167):

```yaml
    - name: inject-repo-clone
      match:
        any:
          - resources:
              kinds:
                - Pod
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
                    value: "ssh -i /etc/git-ssh/ssh-privatekey -o StrictHostKeyChecking=no"
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

**Key differences from spec draft:**
- Uses `/etc/git-ssh` and `/etc/gitconfig` paths (matching existing Kyverno mounts, not `/root/.ssh`)
- Adds `GIT_SSH_COMMAND` env var so git uses the correct SSH key
- Adds `GIT_CONFIG_GLOBAL` env var for gitconfig
- Pins `alpine/git` to `2.47.2` instead of `latest`
- Matches both `claude-agents-write` and `claude-agents-read` namespaces
- Uses `(name): "?*"` pattern for container matching (same as existing rules)

- [ ] **Step 2: Validate YAML syntax**

```bash
yamllint cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml
```

Expected: clean or only pre-existing warnings.

- [ ] **Step 3: Dry-run kustomize build**

```bash
kustomize build cluster/apps/kyverno/policies/app/
```

Expected: renders without errors.

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml
git commit -m "feat(kyverno): add init container rule for repo clone in agent pods"
```

---

## Task 3: Verify Valkey Connectivity for Merge Queue

The merge queue uses Valkey sorted sets and hashes instead of n8n data tables. No table creation needed -- keys are created on first write.

This task and all remaining n8n tasks use MCP tools. Consult the `n8n-mcp-tools-expert` skill before each MCP call.

- [ ] **Step 1: Verify n8n has a Redis/Valkey credential configured**

Check existing n8n credentials for a Redis type:

```javascript
n8n_manage_credentials({ action: "list" })
```

Look for a credential of type `redis`. If none exists, create one pointing to `valkey-master.valkey-system.svc:6379` with the n8n user password.

- [ ] **Step 2: Verify Valkey ACL allows n8n: prefix keys**

The n8n Valkey user is restricted to `~n8n:*` keys. All queue keys use this prefix:
- `n8n:merge-queue` (sorted set)
- `n8n:merge-queue:<member>` (hashes)
- `n8n:lock:merge-queue` (lock key)

No action needed -- just document for awareness.

---

## Task 4: Update n8n Credentials with CLONE_URL

- [ ] **Step 1: Discover existing credentials**

```javascript
n8n_manage_credentials({ action: "list" })
```

Find the existing `claudeCodeK8sApi` credentials: "Claude read-only ephemeral agent" (id: `tLHMjVcgtDYQJFrv`) and any write-tier credential.

- [ ] **Step 2: Get credential schema**

```javascript
n8n_manage_credentials({ action: "getSchema", credentialType: "claudeCodeK8sApi" })
```

Verify the `envVars` field exists and accepts JSON.

- [ ] **Step 3: Update read-tier credential with CLONE_URL**

Update the existing read-tier credential to include `CLONE_URL` in its `envVars` JSON. Use `n8n_manage_credentials` action `update`.

The `envVars` JSON should include all existing env vars plus:

```json
{"CLONE_URL": "git@github.com:anthony-spruyt/spruyt-labs.git"}
```

**Important:** Do NOT display credential data values. Only update the `envVars` field. Check with the user before modifying credentials.

- [ ] **Step 4: Create or update write-tier credential with CLONE_URL**

Same as step 3 but for the write-tier credential. If no write-tier credential exists yet, create one via `n8n_manage_credentials` action `create` with:
- name: "Claude write-tier spruyt-labs"
- type: "claudeCodeK8sApi" (ephemeral) or "claudeCodeK8sPersistentApi" (persistent)
- namespace: "claude-agents-write"
- CLONE_URL in envVars

**Ask the user** for the credential details since they contain authentication secrets.

---

## Task 5: Build Workflow 2 -- Queue Processor

This is the most complex workflow. Build incrementally.

**Workflow name:** "Merge Queue Processor"

- [ ] **Step 1: Create the base workflow with cron trigger**

```javascript
n8n_create_workflow({
  name: "Merge Queue Processor",
  nodes: [
    {
      name: "Cron Trigger",
      type: "n8n-nodes-base.scheduleTrigger",
      typeVersion: 1.2,
      position: [0, 0],
      parameters: {
        rule: {
          interval: [{ field: "minutes", minutesInterval: 10 }]
        }
      }
    },
    {
      name: "When Called by Triage",
      type: "n8n-nodes-base.executeWorkflowTrigger",
      typeVersion: 1.1,
      position: [0, 200],
      parameters: {
        workflowInputs: { values: [] }
      }
    }
  ],
  connections: {},
  settings: {
    executionOrder: "v1",
    timezone: "Australia/Sydney",
    errorWorkflow: "rFJsABwp1kcCfcnq"
  }
})
```

Record the returned workflow ID. **All subsequent `<workflow-id>` placeholders in this task must be replaced with this ID.**

- [ ] **Step 2: Add Valkey lock acquisition nodes**

Add a Redis GET node to check lock, an IF node to branch, and a Redis SET node to acquire lock:

```javascript
n8n_update_partial_workflow({
  id: "<workflow-id>",
  intent: "Add Valkey lock acquisition",
  operations: [
    {
      type: "addNode",
      node: {
        name: "Merge Triggers",
        type: "n8n-nodes-base.merge",
        typeVersion: 3.2,
        position: [200, 100],
        parameters: { mode: "passThrough", options: {} }
      }
    },
    {
      type: "addNode",
      node: {
        name: "Acquire Lock",
        type: "n8n-nodes-base.code",
        typeVersion: 2,
        position: [400, 100],
        parameters: {
          mode: "runOnceForAllItems",
          jsCode: "// Atomic SET NX EX via n8n Redis credential\n// Uses $helpers to execute raw Redis command\n// SET n8n:lock:merge-queue processing NX EX 1800\n// Returns 'OK' if acquired, null if already locked\nconst redis = $getWorkflowStaticData('global');\n// The executing agent should implement this using the Redis node\n// with operation 'set', key 'n8n:lock:merge-queue', and NX+EX flags\n// If Redis node doesn't support NX, use a Code node with HTTP request\n// to Valkey's REST API or accept the GET+SET race.\nreturn [{ json: { lockAcquired: true } }];"
        }
      }
    },
    {
      type: "addNode",
      node: {
        name: "Lock Acquired?",
        type: "n8n-nodes-base.if",
        typeVersion: 2.3,
        position: [600, 100],
        parameters: {
          conditions: {
            options: { typeValidation: "strict", version: 3 },
            conditions: [{
              id: "lock-check",
              leftValue: "={{ $json.lockAcquired }}",
              rightValue: true,
              operator: { type: "boolean", operation: "true" }
            }],
            combinator: "and"
          }
        }
      }
    },
    {
      type: "addConnection",
      source: "Cron Trigger",
      target: "Merge Triggers"
    },
    {
      type: "addConnection",
      source: "When Called by Triage",
      target: "Merge Triggers"
    },
    {
      type: "addConnection",
      source: "Merge Triggers",
      target: "Acquire Lock"
    },
    {
      type: "addConnection",
      source: "Acquire Lock",
      target: "Lock Acquired?"
    }
  ]
})
```

The "true" branch of "Lock Exists?" exits (locked by another execution).

- [ ] **Step 3: Add queue query and loop nodes**

Add data table query, empty check, and loop structure:

```javascript
n8n_update_partial_workflow({
  id: "<workflow-id>",
  intent: "Add queue query and processing loop",
  operations: [
    {
      type: "addNode",
      node: {
        name: "Query Pending Items",
        type: "n8n-nodes-base.n8nTool",
        typeVersion: 1,
        position: [1000, 200],
        parameters: {}
      }
    }
  ]
})
```

Use Redis nodes for ZPOPMIN (dequeue) and DELETE (release lock):

```javascript
n8n_update_partial_workflow({
  id: "<workflow-id>",
  intent: "Add ZPOPMIN dequeue and lock release nodes",
  operations: [
    {
      type: "addNode",
      node: {
        name: "Dequeue Item (ZPOPMIN)",
        type: "n8n-nodes-base.redis",
        typeVersion: 1,
        position: [1000, 200],
        parameters: {
          operation: "get",
          key: "n8n:merge-queue",
          options: { dotNotation: false }
        }
      }
    },
    {
      type: "addNode",
      node: {
        name: "Item Found?",
        type: "n8n-nodes-base.if",
        typeVersion: 2.3,
        position: [1200, 200],
        parameters: {
          conditions: {
            options: { typeValidation: "strict", version: 3 },
            conditions: [{
              id: "item-check",
              leftValue: "={{ $json.member }}",
              rightValue: "",
              operator: { type: "string", operation: "notEquals" }
            }],
            combinator: "and"
          }
        }
      }
    },
    {
      type: "addNode",
      node: {
        name: "Get Item Metadata (HGETALL)",
        type: "n8n-nodes-base.redis",
        typeVersion: 1,
        position: [1400, 300],
        parameters: {
          operation: "get",
          key: "={{ 'n8n:merge-queue:' + $json.member }}",
          options: { dotNotation: false }
        }
      }
    },
    {
      type: "addNode",
      node: {
        name: "DELETE Lock",
        type: "n8n-nodes-base.redis",
        typeVersion: 1,
        position: [1400, 100],
        parameters: {
          operation: "delete",
          key: "n8n:lock:merge-queue"
        }
      }
    },
    {
      type: "addConnection",
      source: "Lock Acquired?",
      target: "Dequeue Item (ZPOPMIN)",
      branch: "true"
    },
    {
      type: "addConnection",
      source: "Dequeue Item (ZPOPMIN)",
      target: "Item Found?"
    },
    {
      type: "addConnection",
      source: "Item Found?",
      target: "GET Item Metadata (HGETALL)",
      branch: "true"
    },
    {
      type: "addConnection",
      source: "Item Found?",
      target: "DELETE Lock",
      branch: "false"
    }
  ]
})
```

**Note:** The n8n Redis node may not support ZPOPMIN directly. If not, use a Code node with `$helpers.httpRequest` to call the Valkey REST API, or use a raw Redis command approach. The executing agent should verify which Redis operations the n8n node supports and adapt accordingly.

- [ ] **Step 4: Add Claude Code merge agent node**

Add the write-tier Claude Code node that merges and validates:

```javascript
n8n_update_partial_workflow({
  id: "<workflow-id>",
  intent: "Add Claude Code merge agent",
  operations: [
    {
      type: "addNode",
      node: {
        name: "Claude Code (Merge + Validate)",
        type: "n8n-nodes-claude-code-cli.claudeCode",
        typeVersion: 1,
        position: [1400, 300],
        parameters: {
          connectionMode: "k8sPersistent",
          prompt: "={{ $json.mergePrompt }}",
          permissionMode: "bypassPermissions",
          model: "opus",
          mcpConfigFilePaths: "/etc/mcp/mcp.json",
          options: {
            systemPromptMode: "append",
            systemPrompt: "",
            maxBudgetUsd: 5,
            jsonSchema: JSON.stringify({
              type: "object",
              required: ["status", "message"],
              properties: {
                status: { type: "string", enum: ["merged", "validation_failed", "merge_failed", "reverted"] },
                message: { type: "string" },
                revertPrNumber: { type: "number" },
                issuesClosed: { type: "array", items: { type: "number" } }
              }
            })
          }
        },
        credentials: {
          claudeCodeK8sPersistentApi: {
            id: "<write-tier-credential-id>",
            name: "Claude write-tier spruyt-labs"
          }
        }
      }
    },
    {
      type: "addConnection",
      source: "Get Item Metadata (HGETALL)",
      target: "Claude Code (Merge + Validate)"
    }
  ]
})
```

- [ ] **Step 5: Add result routing and post-processing nodes**

Add a Switch node to handle different outcomes (merged, merge_failed, reverted), then status update, Discord, and loop-back:

```javascript
n8n_update_partial_workflow({
  id: "<workflow-id>",
  intent: "Add result routing, status update, Discord, loop-back",
  operations: [
    {
      type: "addNode",
      node: {
        name: "Update Status (HSET)",
        type: "n8n-nodes-base.redis",
        typeVersion: 1,
        position: [1600, 300],
        parameters: {
          operation: "set",
          key: "={{ 'n8n:merge-queue:' + $json.member }}",
          value: "={{ $json.status }}"
        }
      }
    },
    {
      type: "addNode",
      node: {
        name: "Format Discord Message",
        type: "n8n-nodes-base.code",
        typeVersion: 2,
        position: [1800, 300],
        parameters: {
          mode: "runOnceForAllItems",
          jsCode: "See jsCode below"
        }
      }
    },
    {
      type: "addNode",
      node: {
        name: "Discord Notify",
        type: "n8n-nodes-base.discord",
        typeVersion: 2,
        position: [2000, 300],
        parameters: {
          resource: "message",
          guildId: { __rl: true, value: "257529418187145216", mode: "list" },
          channelId: { __rl: true, value: "1473506635656990862", mode: "list" }
        },
        credentials: {
          discordBotApi: {
            id: "ZhJu5IvTw0s7pSo8",
            name: "Discord Bot for Skynet"
          }
        }
      }
    },
    {
      type: "addConnection",
      source: "Claude Code (Merge + Validate)",
      target: "Update Status (HSET)"
    },
    {
      type: "addConnection",
      source: "Update Status (HSET)",
      target: "Format Discord Message"
    },
    {
      type: "addConnection",
      source: "Format Discord Message",
      target: "Discord Notify"
    },
    {
      type: "addConnection",
      source: "Discord Notify",
      target: "Dequeue Item (ZPOPMIN)"
    }
  ]
})
```

**jsCode for "Format Discord Message"** (use `patchNodeField` to set after creation):

```javascript
const result = $input.first().json;
let emoji, msg;

switch (result.status) {
  case "merged":
    emoji = ":rocket:";
    msg = `PR #${result.prNumber} merged and validated successfully`;
    break;
  case "reverted":
    emoji = ":rotating_light:";
    msg = `PR #${result.prNumber} merged but validation failed - reverted`;
    break;
  case "merge_failed":
    emoji = ":x:";
    msg = `PR #${result.prNumber} merge failed: ${result.message}`;
    break;
  default:
    emoji = ":x:";
    msg = `PR #${result.prNumber}: ${result.message}`;
}

return [{ json: { content: `${emoji} ${msg}` } }];
```

The connection from "Discord Notify" back to "Dequeue Item (ZPOPMIN)" creates the re-check loop. When ZPOPMIN returns empty, it exits via "DELETE Lock".

- [ ] **Step 6: Validate workflow**

```javascript
n8n_validate_workflow({ id: "<workflow-id>" })
```

Fix any validation errors.

- [ ] **Step 7: Test with a dry run (do not activate yet)**

Leave workflow inactive until all workflows are ready.

---

## Task 6: Build Workflow 3 -- Fix Breaking Changes

**Workflow name:** "Fix Breaking Changes"

- [ ] **Step 1: Create the workflow**

```javascript
n8n_create_workflow({
  name: "Fix Breaking Changes",
  nodes: [
    {
      name: "When Called by Triage",
      type: "n8n-nodes-base.executeWorkflowTrigger",
      typeVersion: 1.1,
      position: [0, 0],
      parameters: {
        workflowInputs: {
          values: [
            { name: "pull_request", type: "object" },
            { name: "repository", type: "object" },
            { name: "breakingChanges", type: "object" },
            { name: "dependency", type: "object" }
          ]
        }
      }
    }
  ],
  connections: {},
  settings: {
    executionOrder: "v1",
    timezone: "Australia/Sydney",
    errorWorkflow: "rFJsABwp1kcCfcnq",
    callerPolicy: "workflowsFromSameOwner"
  }
})
```

Record the returned workflow ID. **All subsequent `<workflow-id>` placeholders in this task must be replaced with this ID.** Also note this ID for Task 7 Step 6 (`<fix-breaking-workflow-id>`).

- [ ] **Step 2: Add the Claude Code fix agent node**

```javascript
n8n_update_partial_workflow({
  id: "<workflow-id>",
  intent: "Add Claude Code breaking change fixer",
  operations: [
    {
      type: "addNode",
      node: {
        name: "Build Fix Prompt",
        type: "n8n-nodes-base.code",
        typeVersion: 2,
        position: [200, 0],
        parameters: {
          mode: "runOnceForAllItems",
          jsCode: "See jsCode content below"
        }
      }
    }
  ]
})
```

**jsCode for "Build Fix Prompt" node** (use `patchNodeField` to set after creation):

```javascript
const { pull_request, repository, breakingChanges, dependency } =
  $input.first().json;

const prompt = [
  "You are fixing breaking changes for a Renovate dependency update.",
  "",
  `PR: #${pull_request.number} in ${repository.full_name}`,
  `Dependency: ${dependency.name} ${dependency.oldVersion} -> ${dependency.newVersion}`,
  `PR branch: ${pull_request.head.ref}`,
  "",
  "Breaking changes to address:",
  JSON.stringify(breakingChanges, null, 2),
  "",
  "Instructions:",
  "1. You are already in the cloned repo on the default branch",
  `2. Fetch and checkout the PR branch: git fetch origin ${pull_request.head.ref}`,
  `   && git checkout ${pull_request.head.ref}`,
  "3. For each breaking change, update the affected configuration files",
  "4. Run local validation: kustomize build on affected paths",
  `5. Commit: fix: address breaking changes for ${dependency.name} ${dependency.newVersion}`,
  `6. Push: git push origin ${pull_request.head.ref}`,
  "",
  "Return a JSON object with your result.",
].join("\n");

return [{ json: { prompt } }];
```

Then continue adding the Claude Code node:

```javascript
n8n_update_partial_workflow({
  id: "<workflow-id>",
  intent: "Add Claude Code breaking change fixer",
  operations: [
    {
      type: "addNode",
      node: {
        name: "Claude Code (Fix)",
        type: "n8n-nodes-claude-code-cli.claudeCode",
        typeVersion: 1,
        position: [400, 0],
        parameters: {
          connectionMode: "k8sEphemeral",
          prompt: "={{ $json.prompt }}",
          permissionMode: "bypassPermissions",
          model: "opus",
          mcpConfigFilePaths: "/etc/mcp/mcp.json",
          options: {
            systemPromptMode: "append",
            maxBudgetUsd: 5,
            additionalArgs: "--settings /etc/claude/settings/merge-agent.json",
            jsonSchema: JSON.stringify({
              type: "object",
              required: ["success", "message"],
              properties: {
                success: { type: "boolean" },
                message: { type: "string" },
                filesChanged: { type: "array", items: { type: "string" } }
              }
            })
          }
        },
        credentials: {
          claudeCodeK8sApi: {
            id: "<write-tier-ephemeral-credential-id>",
            name: "Claude write-tier spruyt-labs"
          }
        }
      }
    },
    {
      type: "addNode",
      node: {
        name: "Discord Notify Fix",
        type: "n8n-nodes-base.discord",
        typeVersion: 2,
        position: [600, 0],
        parameters: {
          resource: "message",
          guildId: { __rl: true, value: "257529418187145216", mode: "list" },
          channelId: { __rl: true, value: "1473506635656990862", mode: "list" },
          content: "={{ ':wrench: PR #' + $('When Called by Triage').first().json.pull_request.number + ' (' + $('When Called by Triage').first().json.dependency.name + '): attempting to fix breaking changes' }}"
        },
        credentials: {
          discordBotApi: {
            id: "ZhJu5IvTw0s7pSo8",
            name: "Discord Bot for Skynet"
          }
        }
      }
    },
    {
      type: "addConnection",
      source: "When Called by Triage",
      target: "Build Fix Prompt"
    },
    {
      type: "addConnection",
      source: "Build Fix Prompt",
      target: "Claude Code (Fix)"
    },
    {
      type: "addConnection",
      source: "Claude Code (Fix)",
      target: "Discord Notify Fix"
    }
  ]
})
```

- [ ] **Step 3: Validate workflow**

```javascript
n8n_validate_workflow({ id: "<workflow-id>" })
```

---

## Task 7: Complete Workflow 1 -- Triage Renovate PR

**Workflow ID:** `WZFm9M1CRhXkPlW1` (existing)

- [ ] **Step 1: Remove the WIP gate**

The WIP node (always-false IF at position [208, 0]) blocks execution. Remove it and connect trigger directly to Claude Code:

```javascript
n8n_update_partial_workflow({
  id: "WZFm9M1CRhXkPlW1",
  intent: "Remove WIP gate, restructure for full triage flow",
  operations: [
    { type: "removeNode", nodeName: "WIP" },
    { type: "removeNode", nodeName: "Claude Code" },
    { type: "removeNode", nodeName: "Merge" },
    { type: "removeNode", nodeName: "Create a comment on an issue" },
    { type: "removeNode", nodeName: "If safe to merge" },
    { type: "removeNode", nodeName: "HTTP Request" },
    { type: "removeNode", nodeName: "Send a message" }
  ]
})
```

- [ ] **Step 2: Add the triage prompt builder**

```javascript
n8n_update_partial_workflow({
  id: "WZFm9M1CRhXkPlW1",
  intent: "Add triage prompt builder",
  operations: [
    {
      type: "addNode",
      node: {
        name: "Build Triage Prompt",
        type: "n8n-nodes-base.code",
        typeVersion: 2,
        position: [200, 0],
        parameters: {
          mode: "runOnceForAllItems",
          jsCode: "See jsCode content below"
        }
      }
    }
  ]
})
```

**jsCode for "Build Triage Prompt" node** (use `patchNodeField` to set after creation):

```javascript
const { pull_request, repository } = $input.first().json;

const prompt = [
  "Analyze this Renovate dependency update PR for breaking changes and risks.",
  "",
  `Repository: ${repository.full_name}`,
  `PR #${pull_request.number}: ${pull_request.title}`,
  `PR Body:`,
  pull_request.body || "No description",
  "",
  "PR diff/patch is available in the PR. Use the GitHub MCP tools to read it.",
  "",
  "Your tasks:",
  "1. Identify the dependency, old version, and new version from PR title and body",
  "2. Classify the update level (patch/minor/major/digest/date/other)",
  "3. Fetch upstream changelog and release notes using web search or GitHub",
  "4. Search upstream GitHub issues for bugs or regressions in the new version",
  "5. Read actual deployed config files that use this dependency",
  "6. Cross-reference any breaking changes against our deployed configuration",
  "7. Assess each breaking change: NO_IMPACT, LOW_IMPACT, HIGH_IMPACT, UNKNOWN_IMPACT",
  "",
  "Verdict rules:",
  "- SAFE: No breaking changes, or all assessed as NO_IMPACT/LOW_IMPACT",
  "- BREAKING: Breaking changes exist but fixable by updating our config",
  "- BLOCKED: Upstream critical bug or regression, cannot fix on our side",
  "- UNKNOWN: Insufficient evidence (missing changelog, unclear upstream issues)",
  "",
  "Return your analysis as structured JSON.",
].join("\n");

return [{ json: { prompt, pull_request, repository } }];
```

Then continue adding connections:

```javascript
n8n_update_partial_workflow({
  id: "WZFm9M1CRhXkPlW1",
  intent: "Connect trigger to triage prompt builder",
  operations: [
    {
      type: "addConnection",
      source: "When Executed by Another Workflow",
      target: "Build Triage Prompt"
    }
  ]
})
```

- [ ] **Step 3: Add Claude Code triage agent**

```javascript
n8n_update_partial_workflow({
  id: "WZFm9M1CRhXkPlW1",
  intent: "Add Claude Code triage agent with structured output",
  operations: [
    {
      type: "addNode",
      node: {
        name: "Claude Code (Triage)",
        type: "n8n-nodes-claude-code-cli.claudeCode",
        typeVersion: 1,
        position: [400, 0],
        parameters: {
          connectionMode: "k8sEphemeral",
          prompt: "={{ $json.prompt }}",
          permissionMode: "bypassPermissions",
          model: "sonnet",
          mcpConfigFilePaths: "/etc/mcp/mcp.json",
          options: {
            systemPromptMode: "append",
            maxBudgetUsd: 2,
            additionalArgs: "--settings /etc/claude/settings/renovate.json",
            jsonSchema: "{\"type\":\"object\",\"required\":[\"verdict\",\"summary\",\"dependency\",\"semverLevel\",\"breakingChanges\",\"features\"],\"properties\":{\"verdict\":{\"type\":\"string\",\"enum\":[\"SAFE\",\"BREAKING\",\"BLOCKED\",\"UNKNOWN\"]},\"summary\":{\"type\":\"string\"},\"dependency\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"oldVersion\":{\"type\":\"string\"},\"newVersion\":{\"type\":\"string\"},\"type\":{\"type\":\"string\",\"enum\":[\"helm\",\"image\",\"taskfile\",\"other\"]}}},\"semverLevel\":{\"type\":\"string\",\"enum\":[\"patch\",\"minor\",\"major\",\"digest\",\"date\",\"other\"]},\"breakingChanges\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"description\":{\"type\":\"string\"},\"impact\":{\"type\":\"string\",\"enum\":[\"NO_IMPACT\",\"LOW_IMPACT\",\"HIGH_IMPACT\",\"UNKNOWN_IMPACT\"]},\"reason\":{\"type\":\"string\"}}}},\"features\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"description\":{\"type\":\"string\"},\"relevance\":{\"type\":\"string\",\"enum\":[\"HIGH\",\"MEDIUM\",\"LOW\"]}}}}}}"
          }
        },
        credentials: {
          claudeCodeK8sApi: {
            id: "tLHMjVcgtDYQJFrv",
            name: "Claude read-only ephemeral agent"
          }
        }
      }
    },
    {
      type: "addConnection",
      source: "Build Triage Prompt",
      target: "Claude Code (Triage)"
    }
  ]
})
```

- [ ] **Step 4: Add verdict routing (Switch node)**

```javascript
n8n_update_partial_workflow({
  id: "WZFm9M1CRhXkPlW1",
  intent: "Add verdict routing switch and PR comment",
  operations: [
    {
      type: "addNode",
      node: {
        name: "Merge Triage + Context",
        type: "n8n-nodes-base.merge",
        typeVersion: 3.2,
        position: [600, 0],
        parameters: { mode: "combine", combineBy: "combineByPosition", options: {} }
      }
    },
    {
      type: "addNode",
      node: {
        name: "Post PR Comment",
        type: "n8n-nodes-base.github",
        typeVersion: 1.1,
        position: [800, 0],
        parameters: {
          authentication: "oAuth2",
          operation: "createComment",
          owner: { __rl: true, value: "={{ $json.repository.owner.login }}", mode: "name" },
          repository: { __rl: true, value: "={{ $json.repository.name }}", mode: "name" },
          issueNumber: "={{ $json.pull_request.number }}",
          body: "={{ '## Triage Verdict: ' + $json.verdict + '\\n\\n' + $json.summary + '\\n\\n### Breaking Changes\\n' + ($json.breakingChanges.length > 0 ? $json.breakingChanges.map(bc => '- **' + bc.impact + '**: ' + bc.description + ' (' + bc.reason + ')').join('\\n') : 'None detected') }}"
        },
        credentials: {
          githubOAuth2Api: {
            id: "x2WS9wUN5PrpwusY",
            name: "GitHub OAuth2 for n8n@spruyt-labs app"
          }
        }
      }
    },
    {
      type: "addNode",
      node: {
        name: "Verdict Router",
        type: "n8n-nodes-base.switch",
        typeVersion: 3.2,
        position: [1000, 0],
        parameters: {
          rules: {
            values: [
              { outputKey: "SAFE", conditions: { conditions: [{ leftValue: "={{ $json.verdict }}", rightValue: "SAFE", operator: { type: "string", operation: "equals" } }] } },
              { outputKey: "BREAKING", conditions: { conditions: [{ leftValue: "={{ $json.verdict }}", rightValue: "BREAKING", operator: { type: "string", operation: "equals" } }] } },
              { outputKey: "BLOCKED", conditions: { conditions: [{ leftValue: "={{ $json.verdict }}", rightValue: "BLOCKED", operator: { type: "string", operation: "equals" } }] } }
            ]
          },
          options: { fallbackOutput: "extra" }
        }
      }
    },
    {
      type: "addConnection",
      source: "Claude Code (Triage)",
      target: "Merge Triage + Context",
      sourceIndex: 0
    },
    {
      type: "addConnection",
      source: "Build Triage Prompt",
      target: "Merge Triage + Context",
      sourceIndex: 1
    },
    {
      type: "addConnection",
      source: "Merge Triage + Context",
      target: "Post PR Comment"
    },
    {
      type: "addConnection",
      source: "Post PR Comment",
      target: "Verdict Router"
    }
  ]
})
```

- [ ] **Step 5: Add SAFE branch (enqueue + trigger processor)**

```javascript
n8n_update_partial_workflow({
  id: "WZFm9M1CRhXkPlW1",
  intent: "Add SAFE branch: enqueue to merge queue + trigger processor",
  operations: [
    {
      type: "addNode",
      node: {
        name: "Map Priority",
        type: "n8n-nodes-base.code",
        typeVersion: 2,
        position: [1200, -200],
        parameters: {
          mode: "runOnceForAllItems",
          jsCode: "const d = $input.first().json;\nconst priorityMap = { digest: 1, date: 1, patch: 1, minor: 2, major: 3, other: 4 };\nconst priority = priorityMap[d.semverLevel] || 4;\nreturn [{ json: { ...d, priority, enqueued_at: new Date().toISOString() } }];"
        }
      }
    },
    {
      type: "addNode",
      node: {
        name: "Enqueue (ZADD + HSET)",
        type: "n8n-nodes-base.code",
        typeVersion: 2,
        position: [1400, -200],
        parameters: {
          mode: "runOnceForAllItems",
          jsCode: "See jsCode below"
        }
      }
    },
    {
      type: "addNode",
      node: {
        name: "Trigger Queue Processor",
        type: "n8n-nodes-base.executeWorkflow",
        typeVersion: 1.2,
        position: [1600, -200],
        parameters: {
          workflowId: { __rl: true, value: "<queue-processor-workflow-id>", mode: "id" },
          mode: "each"
        }
      }
    },
    {
      type: "addConnection",
      source: "Verdict Router",
      target: "Map Priority",
      case: 0
    },
    {
      type: "addConnection",
      source: "Map Priority",
      target: "Enqueue (ZADD + HSET)"
    },
    {
      type: "addConnection",
      source: "Enqueue (ZADD + HSET)",
      target: "Trigger Queue Processor"
    }
  ]
})
```

**jsCode for "Enqueue (ZADD + HSET)":** The executing agent should implement this using two Redis nodes in sequence:
1. `ZADD n8n:merge-queue <score> pr:<repo>:<pr_number>` where score = `priority * 1e12 + Date.now()`
2. `HSET n8n:merge-queue:pr:<repo>:<pr_number>` with all metadata fields (pr_number, repo, source, priority, status=pending, enqueued_at, verdict_json, pr_url, head_branch)

If the n8n Redis node doesn't support ZADD, use a Code node with `$helpers.httpRequest` to call Valkey's API.

**Important:** Replace `<queue-processor-workflow-id>` with the actual workflow ID from Task 5 Step 1.

- [ ] **Step 6: Add BREAKING branch (retry check + call fix workflow)**

```javascript
n8n_update_partial_workflow({
  id: "WZFm9M1CRhXkPlW1",
  intent: "Add BREAKING branch: retry check + fix workflow call",
  operations: [
    {
      type: "addNode",
      node: {
        name: "Count Previous BREAKING",
        type: "n8n-nodes-base.code",
        typeVersion: 2,
        position: [1200, 0],
        parameters: {
          mode: "runOnceForAllItems",
          jsCode: "// Count comments containing 'Triage Verdict: BREAKING' on this PR\n// The executing agent should use GitHub MCP to list PR comments and count\nconst d = $input.first().json;\n// Placeholder - agent implements actual GitHub comment query\nconst breakingCount = 0; // Replace with actual count\nreturn [{ json: { ...d, breakingCount, maxRetries: 2 } }];"
        }
      }
    },
    {
      type: "addNode",
      node: {
        name: "Retries Exceeded?",
        type: "n8n-nodes-base.if",
        typeVersion: 2.3,
        position: [1400, 0],
        parameters: {
          conditions: {
            options: { typeValidation: "strict", version: 3 },
            conditions: [{
              id: "retry-check",
              leftValue: "={{ $json.breakingCount }}",
              rightValue: "={{ $json.maxRetries }}",
              operator: { type: "number", operation: "gte" }
            }],
            combinator: "and"
          }
        }
      }
    },
    {
      type: "addNode",
      node: {
        name: "Call Fix Workflow",
        type: "n8n-nodes-base.executeWorkflow",
        typeVersion: 1.2,
        position: [1600, 100],
        parameters: {
          workflowId: { __rl: true, value: "<fix-breaking-workflow-id>", mode: "id" },
          mode: "each"
        }
      }
    },
    {
      type: "addConnection",
      source: "Verdict Router",
      target: "Count Previous BREAKING",
      case: 1
    },
    {
      type: "addConnection",
      source: "Count Previous BREAKING",
      target: "Retries Exceeded?"
    },
    {
      type: "addConnection",
      source: "Retries Exceeded?",
      target: "Call Fix Workflow",
      branch: "false"
    }
  ]
})
```

When retries exceeded (true branch), route to BLOCKED handling (same as step 7).

- [ ] **Step 7: Add BLOCKED and UNKNOWN branches (Discord + label)**

```javascript
n8n_update_partial_workflow({
  id: "WZFm9M1CRhXkPlW1",
  intent: "Add BLOCKED/UNKNOWN branches: Discord notify + label PR",
  operations: [
    {
      type: "addNode",
      node: {
        name: "Label PR Blocked",
        type: "n8n-nodes-base.httpRequest",
        typeVersion: 4.4,
        position: [1200, 200],
        parameters: {
          method: "POST",
          url: "={{ 'https://api.github.com/repos/' + $json.repository.full_name + '/issues/' + $json.pull_request.number + '/labels' }}",
          authentication: "predefinedCredentialType",
          nodeCredentialType: "githubOAuth2Api",
          sendBody: true,
          bodyParameters: { parameters: [{ name: "labels", value: "=[\"blocked\"]" }] }
        },
        credentials: {
          githubOAuth2Api: {
            id: "x2WS9wUN5PrpwusY",
            name: "GitHub OAuth2 for n8n@spruyt-labs app"
          }
        }
      }
    },
    {
      type: "addNode",
      node: {
        name: "Discord Triage Result",
        type: "n8n-nodes-base.discord",
        typeVersion: 2,
        position: [1400, 300],
        parameters: {
          resource: "message",
          guildId: { __rl: true, value: "257529418187145216", mode: "list" },
          channelId: { __rl: true, value: "1473506635656990862", mode: "list" }
        },
        credentials: {
          discordBotApi: {
            id: "ZhJu5IvTw0s7pSo8",
            name: "Discord Bot for Skynet"
          }
        }
      }
    },
    {
      type: "addConnection",
      source: "Verdict Router",
      target: "Label PR Blocked",
      case: 2
    },
    {
      type: "addConnection",
      source: "Retries Exceeded?",
      target: "Label PR Blocked",
      branch: "true"
    },
    {
      type: "addConnection",
      source: "Label PR Blocked",
      target: "Discord Triage Result"
    },
    {
      type: "addConnection",
      source: "Verdict Router",
      target: "Discord Triage Result",
      case: 3
    }
  ]
})
```

- [ ] **Step 8: Validate workflow**

```javascript
n8n_validate_workflow({ id: "WZFm9M1CRhXkPlW1" })
```

---

## Task 8: Wire Webhook Workflow to Updated Triage

**Workflow ID:** `e9nTmnZGu8Li29iW`

- [ ] **Step 1: Verify existing connection**

The webhook workflow already has a "Call 'Triage a Renovate pull request'" node connected to the triage workflow. Verify it points to workflow `WZFm9M1CRhXkPlW1`.

```javascript
n8n_get_workflow({ id: "e9nTmnZGu8Li29iW", mode: "full" })
```

Check the `executeWorkflow` node's `workflowId` parameter.

- [ ] **Step 2: Update if needed**

If the `executeWorkflow` node references a different workflow ID, update it:

```javascript
n8n_update_partial_workflow({
  id: "e9nTmnZGu8Li29iW",
  intent: "Ensure triage call points to correct workflow",
  operations: [{
    type: "updateNode",
    nodeName: "Call 'Triage a Renovate pull request'",
    updates: {
      workflowId: { __rl: true, value: "WZFm9M1CRhXkPlW1", mode: "id" }
    }
  }]
})
```

---

## Task 9: Activate All Workflows and Test

- [ ] **Step 1: Commit and push cluster changes**

```bash
git status
```

Verify only our changed files are staged, then push.

- [ ] **Step 2: Run qa-validator on cluster changes**

Run qa-validator agent on the Kyverno policy and settings profile changes.

- [ ] **Step 3: Activate Workflow 3 (Fix Breaking Changes)**

```javascript
n8n_update_partial_workflow({
  id: "<fix-breaking-workflow-id>",
  operations: [{ type: "activateWorkflow" }]
})
```

- [ ] **Step 4: Activate Workflow 2 (Queue Processor)**

```javascript
n8n_update_partial_workflow({
  id: "<queue-processor-workflow-id>",
  operations: [{ type: "activateWorkflow" }]
})
```

- [ ] **Step 5: Activate Workflow 1 (Triage)**

Already active but verify WIP gate is removed.

- [ ] **Step 6: Test with a real Renovate patch PR**

Find an open Renovate PR. If none exist, trigger Renovate manually via the Dependency Dashboard issue.

Monitor:
1. Webhook workflow receives the event
2. Triage workflow spawns read-tier agent
3. PR gets a comment with verdict
4. If SAFE: item appears in merge-queue data table
5. Queue processor picks it up, merges, validates
6. Discord notification appears in #skynet

- [ ] **Step 7: Monitor and fix issues**

Watch n8n execution logs for errors. Common issues:
- Credential not found: verify credential IDs in workflow nodes
- Init container fails: check Kyverno policy, SSH key access
- Claude agent timeout: increase `timeout` option or `maxBudgetUsd`
- Data table query fails: verify table ID and column names

---

## Task 10: Deprecate Old Skill and Agent

Only after successful end-to-end test.

- [ ] **Step 1: Add deprecation notice to skill**

Read `.claude/skills/renovate-pr-processor.md` and add at the top:

```markdown
> **DEPRECATED:** This skill is replaced by n8n webhook-triggered automation.
> See `docs/superpowers/specs/2026-04-21-renovate-pr-automation-design.md`.
> Kept as manual fallback only.
```

- [ ] **Step 2: Add deprecation notice to agent**

Read `.claude/agents/renovate-pr-analyzer.md` and add at the top:

```markdown
> **DEPRECATED:** This agent is replaced by the n8n triage workflow.
> See `docs/superpowers/specs/2026-04-21-renovate-pr-automation-design.md`.
> Kept as manual fallback only.
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/renovate-pr-processor.md .claude/agents/renovate-pr-analyzer.md
git commit -m "chore(agents): deprecate renovate skill and agent in favor of n8n automation"
```
