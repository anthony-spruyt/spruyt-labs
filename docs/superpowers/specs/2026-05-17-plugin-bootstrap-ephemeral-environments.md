# Bootstrap Claude Code Plugins in Ephemeral Environments

**Issue:** [#1528](https://github.com/anthony-spruyt/spruyt-labs/issues/1528) **Date:** 2026-05-17

## Problem

Claude Code CLI does not auto-install plugins declared in `enabledPlugins` / `extraKnownMarketplaces` settings. Upstream issues:

- [anthropics/claude-code#45323](https://github.com/anthropics/claude-code/issues/45323)
- [anthropics/claude-code#16870](https://github.com/anthropics/claude-code/issues/16870)
- [anthropics/claude-code#51118](https://github.com/anthropics/claude-code/issues/51118)

Devcontainers bind-mount `~/.claude` from host — plugins persist. Coder workspaces and cluster agents start fresh — no plugins available.

## Affected Environments

| Environment          | Init Path                                                                      | Settings Source                                                                       |
| -------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| Coder workspace      | `devcontainer-post-create` (baked into `devcontainer-common` image)            | `.claude/settings.json` from cloned repo                                              |
| Cluster agent        | Kyverno-injected init containers on pods labeled `managed-by: n8n-claude-code` | `managed-settings.json` ConfigMap mounted at `/etc/claude-code/managed-settings.json` |
| Devcontainer (local) | Host `~/.claude` bind-mount                                                    | **Not affected** — plugins persist                                                    |

## Design

### Core Logic

A shell script that reads any Claude Code settings JSON and dynamically installs declared marketplaces and plugins. No hardcoded plugin names.

```bash
bootstrap_claude_plugins() {
  local settings_file="$1"
  [ -f "$settings_file" ] || return 0

  # Add custom marketplaces
  jq -r '.extraKnownMarketplaces // {} | to_entries[] | "\(.key) \(.value.source.repo)"' \
    "$settings_file" 2>/dev/null | while read -r name repo; do
    echo "[plugin-bootstrap] marketplace add: $name ($repo)"
    claude plugins marketplace add "$repo" --scope user 2>/dev/null || true
  done

  # Install enabled plugins
  jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' \
    "$settings_file" 2>/dev/null | while read -r plugin; do
    echo "[plugin-bootstrap] install: $plugin"
    claude plugins install "$plugin" --scope user 2>/dev/null || true
  done
}
```

Key properties:

- **Dynamic:** reads JSON, installs whatever is declared
- **`--scope user`:** writes to `~/.claude/`, never modifies git-tracked project files
- **Idempotent:** `marketplace add` and `plugins install` are no-ops when already present
- **Fault-tolerant:** `|| true` on each command — one failure doesn't block others
- **Authenticated GitHub access:** init container mounts `gh-config-writable` for 5,000 req/hr rate limit (vs 60 unauthenticated). Prevents rate limiting during burst pod startups

### Cluster Agents — Kyverno Init Container

Add `plugin-bootstrap` init container to the `inject-shared-config` rule in `inject-claude-agent-config.yaml`. Same init container technique as `git-clone` (uses main container image, security context, volume sharing) but placed in `inject-shared-config` since all agent namespaces need plugins.

New volume:

```yaml
- name: claude-home
  emptyDir:
    sizeLimit: 256Mi
```

New init container:

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
      drop: [ALL]
    runAsNonRoot: true
```

Main container also mounts the shared volume:

```yaml
containers:
  - (name): "?*"
    volumeMounts:
      - name: claude-home
        mountPath: /home/node/.claude
```

Dependencies: `jq` and `claude` CLI are both in the agent container image (`claude-agent-spruyt-labs` Dockerfile).

### Coder / Devcontainer — post-create.sh

Add plugin bootstrap to `devcontainer-common/assets/post-create.sh` in `container-images` repo. Placed after Claude CLI installation. Reads both `settings.json` and `settings.local.json` (the latter contains workspace-specific plugins like `n8n-mcp-skills` that aren't in the main settings):

```bash
# Bootstrap Claude Code plugins from project settings
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

if command -v claude &>/dev/null; then
  echo "Bootstrapping Claude Code plugins..."
  bootstrap_claude_plugins "$WORKSPACE/.claude/settings.json"
  bootstrap_claude_plugins "$WORKSPACE/.claude/settings.local.json"
fi
```

## Deliverables

| Deliverable            | Repo                      | File                                                                |
| ---------------------- | ------------------------- | ------------------------------------------------------------------- |
| Kyverno init container | spruyt-labs               | `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml` |
| post-create.sh update  | container-images          | `devcontainer-common/assets/post-create.sh`                         |
| n8n node               | n8n-nodes-claude-code-cli | **No changes needed**                                               |

## Edge Cases Tested

| Scenario                       | Behavior                                               |
| ------------------------------ | ------------------------------------------------------ |
| Missing settings file          | `[ -f ]` guard skips entirely                          |
| Empty JSON `{}`                | `// {}` fallback produces empty output, no iterations  |
| No plugin/marketplace keys     | `// {}` fallback, no iterations                        |
| All plugins disabled (`false`) | `select(.value == true)` filters them out              |
| Invalid JSON                   | jq errors to stderr, `\|\| true` catches it, continues |
| Nonexistent marketplace repo   | CLI exits 1, `\|\| true` catches it, continues to next |
| Nonexistent plugin name        | CLI exits 1, `\|\| true` catches it, continues to next |
| Already-installed plugin       | CLI reports "already installed", exits 0               |

## Removal Condition

Delete bootstrap logic when upstream auto-install fixes land. Track:

- [anthropics/claude-code#45323](https://github.com/anthropics/claude-code/issues/45323)
- [anthropics/claude-code#16870](https://github.com/anthropics/claude-code/issues/16870)
- [anthropics/claude-code#51118](https://github.com/anthropics/claude-code/issues/51118)
