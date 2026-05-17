# Plugin Bootstrap for Ephemeral Environments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-install Claude Code plugins from settings JSON at startup in cluster agent pods and Coder devcontainer workspaces.

**Architecture:** Kyverno init container for cluster agents reads `managed-settings.json` ConfigMap and installs marketplaces + plugins via `claude plugins` CLI before the main container starts, sharing installed state through an emptyDir volume. Devcontainer `post-create.sh` does the same from project `.claude/settings.json` and `.claude/settings.local.json`. Both use `--scope user` to write to
`~/.claude/` and avoid dirtying git-tracked project files.

**Tech Stack:** Kyverno ClusterPolicy, Bash, jq, Claude Code CLI

**Spec:** `docs/superpowers/specs/2026-05-17-plugin-bootstrap-ephemeral-environments.md`

**Issue:** [#1528](https://github.com/anthony-spruyt/spruyt-labs/issues/1528)

______________________________________________________________________

## File Structure

| Action | File                                                                | Repo             | Responsibility                                                                                  |
| ------ | ------------------------------------------------------------------- | ---------------- | ----------------------------------------------------------------------------------------------- |
| Modify | `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml` | spruyt-labs      | Add `claude-home` volume, `plugin-bootstrap` init container, main container `claude-home` mount |
| Modify | `devcontainer-common/assets/post-create.sh`                         | container-images | Add `bootstrap_claude_plugins()` function after Claude CLI install                              |

______________________________________________________________________

### Task 1: Add plugin-bootstrap to Kyverno inject-shared-config rule

**Files:**

- Modify: `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml:98-237` (the `inject-shared-config` rule)

Three changes in the `inject-shared-config` rule's `mutate.patchStrategicMerge.spec`:

- [ ] **Step 1: Add `claude-home` emptyDir volume**

In the `volumes` list (after the existing `claude-managed-settings` volume at line 133), add:

```yaml
              - name: claude-home
                emptyDir:
                  sizeLimit: 256Mi
```

The full volumes list after edit:

```yaml
            volumes:
              - name: github-gh-config
                secret:
                  secretName: github-bot-credentials
                  items:
                    - key: hosts.yml
                      path: hosts.yml
              - name: gh-config-writable
                emptyDir: {}
              - name: github-gitconfig
                configMap:
                  name: github-bot-gitconfig-read
              - name: claude-settings-profiles
                configMap:
                  name: claude-settings-profiles
              - name: claude-managed-settings
                configMap:
                  name: claude-managed-settings
              - name: claude-home
                emptyDir:
                  sizeLimit: 256Mi
```

- [ ] **Step 2: Add `plugin-bootstrap` init container**

After the existing `gh-config-sync` init container (ends at line 164), add the `plugin-bootstrap` init container. It must come after `gh-config-sync` because it depends on the gh credential file being copied to `/tmp/gh-config/` for authenticated GitHub API access. The init container:

- Uses the main container's image (has both `jq` and `claude` CLI baked in)
- Sets `HOME=/home/node` explicitly (Kubernetes init containers don't always inherit the image's HOME from `/etc/passwd`)
- Sets `GH_CONFIG_DIR=/tmp/gh-config` for authenticated GitHub access (5,000 req/hr vs 60 unauthenticated)
- Reads `managed-settings.json` from ConfigMap mount
- Adds custom marketplaces first, then installs enabled plugins
- Each command uses `|| true` — one failure doesn't block others
- Writes installed plugins to `/home/node/.claude/` via the shared `claude-home` emptyDir

```yaml
              - name: plugin-bootstrap
                image: "{{ request.object.spec.containers[0].image }}"
                command: ["sh", "-c"]
                env:
                  - name: HOME
                    value: /home/node
                  - name: GH_CONFIG_DIR
                    value: /tmp/gh-config
                args:
                  - |
                    SETTINGS="/etc/claude-code/managed-settings.json"
                    [ -f "$SETTINGS" ] || { echo "[plugin-bootstrap] no settings, skip"; exit 0; }
                    echo "[plugin-bootstrap] reading $SETTINGS"
                    jq -r '.extraKnownMarketplaces // {} | to_entries[] | "\(.key) \(.value.source.repo)"' "$SETTINGS" | while read -r name repo; do
                      echo "[plugin-bootstrap] marketplace add: $name ($repo)"
                      claude plugins marketplace add "$repo" --scope user || true
                    done
                    jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "$SETTINGS" | while read -r plugin; do
                      echo "[plugin-bootstrap] install: $plugin"
                      claude plugins install "$plugin" --scope user || true
                    done
                    echo "[plugin-bootstrap] done"
                volumeMounts:
                  - name: claude-managed-settings
                    mountPath: /etc/claude-code/managed-settings.json
                    subPath: managed-settings.json
                    readOnly: true
                  - name: gh-config-writable
                    mountPath: /tmp/gh-config
                  - name: claude-home
                    mountPath: /home/node/.claude
                securityContext:
                  allowPrivilegeEscalation: false
                  readOnlyRootFilesystem: false
                  capabilities:
                    drop:
                      - ALL
                  runAsNonRoot: true
```

- [ ] **Step 3: Add `claude-home` volumeMount to main container**

In the `containers` section's `volumeMounts` list (after the existing `claude-managed-settings` mount at line 237), add:

```yaml
                  - name: claude-home
                    mountPath: /home/node/.claude
```

The full volumeMounts list for the main container after edit:

```yaml
                volumeMounts:
                  - name: github-gh-config
                    mountPath: /etc/gh-secret
                    readOnly: true
                  - name: gh-config-writable
                    mountPath: /tmp/gh-config
                  - name: github-gitconfig
                    mountPath: /etc/git-config
                    readOnly: true
                  - name: claude-settings-profiles
                    mountPath: /etc/claude/settings
                    readOnly: true
                  - name: claude-managed-settings
                    mountPath: /etc/claude-code/managed-settings.json
                    subPath: managed-settings.json
                    readOnly: true
                  - name: claude-home
                    mountPath: /home/node/.claude
```

- [ ] **Step 4: Update policy description annotation**

Update the `policies.kyverno.io/description` annotation at line 12 to mention plugin bootstrap. Replace:

```yaml
    policies.kyverno.io/description: >-
      Injects configuration into Claude agent pods spawned by n8n.
      A shared rule injects GitHub bot credentials (gh CLI config,
      read-only gitconfig), settings profiles, Context7 API key,
      agentmemory connection, and OpenTelemetry env vars into all
      agent namespaces. The write rule
      additionally injects SSH key and full gitconfig (with commit
      signing). Per-namespace rules inject MCP configmaps, priority
      classes, and namespace-specific credentials. Repo clone: write
      uses SSH (with pre-commit), read+sre use HTTPS with read-scoped
      GitHub App token (no SSH key = no push capability). Validation
      rules enforce correct CLONE_URL protocol per namespace tier.
```

With:

```yaml
    policies.kyverno.io/description: >-
      Injects configuration into Claude agent pods spawned by n8n.
      A shared rule injects GitHub bot credentials (gh CLI config,
      read-only gitconfig), settings profiles, plugin bootstrap,
      Context7 API key, agentmemory connection, and OpenTelemetry
      env vars into all agent namespaces. The write rule
      additionally injects SSH key and full gitconfig (with commit
      signing). Per-namespace rules inject MCP configmaps, priority
      classes, and namespace-specific credentials. Repo clone: write
      uses SSH (with pre-commit), read+sre use HTTPS with read-scoped
      GitHub App token (no SSH key = no push capability). Validation
      rules enforce correct CLONE_URL protocol per namespace tier.
```

- [ ] **Step 5: Validate YAML syntax**

Run:

```bash
yamllint cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml
```

Expected: no errors (warnings about line length are acceptable).

- [ ] **Step 6: Commit**

```bash
git add cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml
git commit -m "feat(claude-agents): add plugin-bootstrap init container to Kyverno policy

Adds an init container to the inject-shared-config rule that reads
managed-settings.json and installs declared marketplaces + plugins
via claude CLI before the main container starts. Uses shared emptyDir
volume for ~/.claude state and authenticated GitHub access via
gh-config-writable.

Ref #1528"
```

______________________________________________________________________

### Task 2: Add plugin bootstrap to devcontainer post-create.sh

**Files:**

- Modify: `devcontainer-common/assets/post-create.sh` in `anthony-spruyt/container-images` repo

This is a cross-repo change. Clone or fork the `container-images` repo, make the change, and open a PR.

- [ ] **Step 1: Clone the container-images repo**

```bash
gh repo clone anthony-spruyt/container-images /tmp/container-images
cd /tmp/container-images
git checkout -b feat/plugin-bootstrap
```

- [ ] **Step 2: Add `bootstrap_claude_plugins()` function**

In `devcontainer-common/assets/post-create.sh`, after the Claude CLI installation block (after the line `grep -q 'local/bin' "$HOME/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$HOME/.bashrc"`), add:

```bash
# Bootstrap Claude Code plugins from project settings
if command -v claude &>/dev/null && command -v jq &>/dev/null; then
  bootstrap_claude_plugins() {
    local settings_file="$1"
    [ -f "$settings_file" ] || return 0
    echo "  reading $settings_file"
    jq -r '.extraKnownMarketplaces // {} | to_entries[] | .value.source.repo' \
      "$settings_file" 2>/dev/null | while read -r repo; do
      echo "    marketplace: $repo"
      claude plugins marketplace add "$repo" --scope user 2>/dev/null || true
    done
    jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' \
      "$settings_file" 2>/dev/null | while read -r plugin; do
      echo "    install: $plugin"
      claude plugins install "$plugin" --scope user 2>/dev/null || true
    done
  }
  echo "Bootstrapping Claude Code plugins..."
  bootstrap_claude_plugins "$WORKSPACE/.claude/settings.json"
  bootstrap_claude_plugins "$WORKSPACE/.claude/settings.local.json"
fi
```

Key differences from the cluster agent version:

- Guarded by `command -v claude` and `command -v jq` (jq may not be in all devcontainer images)

- Reads from cloned repo's `.claude/settings.json` and `.claude/settings.local.json` (not a ConfigMap)

- Reads both files because `settings.local.json` contains workspace-specific plugins (e.g., `n8n-mcp-skills`) that aren't in the main settings

- Uses `2>/dev/null` on jq calls (suppresses errors to avoid noise in post-create output)

- [ ] **Step 3: Validate syntax**

```bash
shellcheck devcontainer-common/assets/post-create.sh
```

Expected: no new errors. Existing `SC2016` suppressions are fine.

- [ ] **Step 4: Commit and push**

```bash
git add devcontainer-common/assets/post-create.sh
git commit -m "feat(devcontainer): bootstrap Claude Code plugins from project settings

Adds bootstrap_claude_plugins() to post-create.sh that reads
.claude/settings.json and .claude/settings.local.json, installs
declared marketplaces and plugins via claude CLI --scope user.
Guarded by jq + claude availability checks.

Ref anthony-spruyt/spruyt-labs#1528"
git push -u origin feat/plugin-bootstrap
```

- [ ] **Step 5: Create PR**

```bash
gh pr create --repo anthony-spruyt/container-images \
  --title "feat(devcontainer): bootstrap Claude Code plugins from project settings" \
  --body "$(cat <<'BODY'
## Summary
- Adds `bootstrap_claude_plugins()` function to `devcontainer-common/assets/post-create.sh`
- Reads `.claude/settings.json` and `.claude/settings.local.json` from cloned workspace
- Dynamically installs declared marketplaces and enabled plugins via `claude plugins` CLI
- Uses `--scope user` to write to `~/.claude/` (avoids dirtying git state)

## Linked Issue
Ref anthony-spruyt/spruyt-labs#1528

## Changes
- Add `bootstrap_claude_plugins()` function after Claude CLI installation
- Guard with `command -v claude && command -v jq` availability check
- Read both `settings.json` and `settings.local.json` (local has workspace-specific plugins)

## Testing
- Function tested in devcontainer environment with real `claude plugins` CLI commands
- Edge cases verified: missing file, empty JSON, disabled plugins, invalid JSON, already-installed plugins
- All commands idempotent and fault-tolerant (`|| true`)
BODY
)"
```

______________________________________________________________________

### Task 3: Push spruyt-labs changes and validate

- [ ] **Step 1: Push to main**

```bash
git push
```

Flux webhook auto-reconciles — no manual `flux reconcile` needed.

- [ ] **Step 2: Run cluster-validator**

After push, run the `cluster-validator` agent to verify:

- Kyverno ClusterPolicy reconciles without errors

- Policy report shows no violations

- Next agent pod spawn includes the `plugin-bootstrap` init container

- [ ] **Step 3: Verify init container in a live pod**

After an agent pod spawns (or trigger one via n8n), verify the init container ran:

```bash
kubectl get pods -l managed-by=n8n-claude-code -n claude-agents-spruyt-labs-sre --sort-by=.metadata.creationTimestamp | tail -1
```

Check init container logs:

```bash
kubectl logs <pod-name> -n claude-agents-spruyt-labs-sre -c plugin-bootstrap
```

Expected output:

```text
[plugin-bootstrap] reading /etc/claude-code/managed-settings.json
[plugin-bootstrap] marketplace add: hookify-plus (anthony-spruyt/hookify-plus)
[plugin-bootstrap] marketplace add: agentmemory (rohitg00/agentmemory)
[plugin-bootstrap] install: hookify-plus@hookify-plus
[plugin-bootstrap] install: agentmemory@agentmemory
[plugin-bootstrap] done
```

- [ ] **Step 4: Close issue after both PRs merge and validate**

Post validation results as a comment on [#1528](https://github.com/anthony-spruyt/spruyt-labs/issues/1528), then close.

______________________________________________________________________

## Removal Condition

Delete bootstrap logic when upstream auto-install lands. Track:

- [anthropics/claude-code#45323](https://github.com/anthropics/claude-code/issues/45323)
- [anthropics/claude-code#16870](https://github.com/anthropics/claude-code/issues/16870)
- [anthropics/claude-code#51118](https://github.com/anthropics/claude-code/issues/51118)
