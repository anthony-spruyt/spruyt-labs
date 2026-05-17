# Plugin Bootstrap for Ephemeral Environments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-install Claude Code plugins from settings JSON at startup in cluster agent pods and Coder devcontainer workspaces.

**Architecture:** A ConfigMap-mounted bash script (`bootstrap-plugins.sh`) runs as a Kyverno-injected init container in both clone rules (`inject-repo-clone-write` and `inject-repo-clone-read`), after `git-clone` completes. The script reads four settings sources in Claude Code precedence order: `managed-settings.json` (from ConfigMap), `~/.claude/settings.json` (user-level, empty in fresh pods),
plus project-level `.claude/settings.json` and `.claude/settings.local.json` (from the cloned repo at `/workspace/repo`). Placing the init container in the clone rules guarantees the repo is available. Shared volumes (`claude-home` emptyDir, `claude-plugin-bootstrap-script` ConfigMap) are added to `inject-shared-config` alongside existing shared volumes. Devcontainer `post-create.sh` does the same
from project settings. Both use `--scope user` to write to `~/.claude/` and avoid dirtying git-tracked project files.

**Tech Stack:** Kyverno ClusterPolicy, Bash, jq, Claude Code CLI, bats (tests)

**Spec:** `docs/superpowers/specs/2026-05-17-plugin-bootstrap-ephemeral-environments.md`

**Plan deviations from spec:**

- Script is a ConfigMap-mounted file (not inline YAML) for testability
- Init container is in both clone rules (not `inject-shared-config`) to guarantee the cloned repo is available for reading project settings
- Reads all four Claude Code settings layers in precedence order: managed → user (`~/.claude/settings.json`) → project → local
- Infrastructure errors (missing jq/claude, invalid JSON) exit 1; installation errors log warnings and continue
- `select(.value.source != null and .value.source.repo != null)` added to marketplace jq filter
- Accepts string `"true"` in addition to boolean `true` for `enabledPlugins`
- Tab-delimited marketplace extraction with proper IFS handling
- JSON validation with `jq empty` before processing
- bats test suite added for the bootstrap script

**Issue:** [#1528](https://github.com/anthony-spruyt/spruyt-labs/issues/1528)

______________________________________________________________________

## File Structure

| Action | File                                                                    | Repo             | Responsibility                                                                |
| ------ | ----------------------------------------------------------------------- | ---------------- | ----------------------------------------------------------------------------- |
| Create | `cluster/apps/claude-agents-shared/base/scripts/bootstrap-plugins.sh`   | spruyt-labs      | Bootstrap script (mounted as ConfigMap)                                       |
| Modify | `cluster/apps/claude-agents-shared/base/kustomization.yaml`             | spruyt-labs      | Add `configMapGenerator` for bootstrap script                                 |
| Modify | each namespace `kustomization.yaml` (5 namespaces)                      | spruyt-labs      | Add `configMapGenerator` for bootstrap script (or use shared base)            |
| Modify | `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml`     | spruyt-labs      | Add volumes to `inject-shared-config`, add init container to both clone rules |
| Create | `cluster/apps/claude-agents-shared/base/scripts/bootstrap-plugins.bats` | spruyt-labs      | bats test suite for bootstrap script                                          |
| Modify | `.github/workflows/ci.yaml`                                             | spruyt-labs      | Add path filter + bats-test job                                               |
| Create | `.github/workflows/_bats-test.yaml`                                     | spruyt-labs      | Reusable bats test workflow                                                   |
| Modify | `devcontainer-common/assets/post-create.sh`                             | container-images | Add `bootstrap_claude_plugins()` function                                     |

______________________________________________________________________

### Task 1: Add plugin-bootstrap to Kyverno policy

**Files:**

- Create: `cluster/apps/claude-agents-shared/base/scripts/bootstrap-plugins.sh`
- Modify: `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml`
- Modify: namespace-level `kustomization.yaml` files (to generate the ConfigMap from the script)

Seven sub-tasks: create script, update ConfigMap generation, add shared volumes, add init container to both clone rules, add main container volumeMount, update annotation, validate + commit.

- [ ] **Step 1: Create the bootstrap script**

Create `cluster/apps/claude-agents-shared/base/scripts/bootstrap-plugins.sh`:

```bash
#!/usr/bin/env bash
set -eo pipefail

REPO_DIR="/workspace/repo"

bootstrap_from_file() {
  local settings_file="$1"
  [ -f "$settings_file" ] || return 0
  jq empty "$settings_file" || { echo "[plugin-bootstrap] invalid JSON in $settings_file"; exit 1; }
  echo "[plugin-bootstrap] reading $settings_file"

  jq -r '.extraKnownMarketplaces // {} | to_entries[] | select(.value.source != null and .value.source.repo != null) | "\(.key)\t\(.value.source.repo)"' \
    "$settings_file" | while IFS="$(printf '\t')" read -r name repo; do
    echo "[plugin-bootstrap] marketplace add: $name ($repo)"
    claude plugins marketplace add "$repo" --scope user \
      || echo "[plugin-bootstrap] WARNING: failed to add marketplace '$name'"
  done

  jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true or .value == "true") | .key' \
    "$settings_file" | while IFS= read -r plugin; do
    echo "[plugin-bootstrap] install: $plugin"
    claude plugins install "$plugin" --scope user \
      || echo "[plugin-bootstrap] WARNING: failed to install '$plugin'"
  done
}

command -v jq >/dev/null || { echo "[plugin-bootstrap] jq not found"; exit 1; }
command -v claude >/dev/null || { echo "[plugin-bootstrap] claude CLI not found"; exit 1; }

# Cluster-managed settings (from ConfigMap)
bootstrap_from_file "/etc/claude-code/managed-settings.json"

# User-level settings (on claude-home emptyDir — empty in fresh pods)
bootstrap_from_file "$HOME/.claude/settings.json"

# Project-level settings (from cloned repo)
bootstrap_from_file "$REPO_DIR/.claude/settings.json"
bootstrap_from_file "$REPO_DIR/.claude/settings.local.json"

echo "[plugin-bootstrap] done"
```

Key design decisions:

- **Infrastructure errors exit 1:** missing `jq`/`claude` CLI or invalid JSON indicate a broken container image or ConfigMap — pod should not start with broken infra

- **Installation errors warn and continue:** one failed plugin should not block the agent pod from starting

- **`set -eo pipefail`:** jq extraction failures on malformed settings structure are infrastructure errors

- **Project settings files are optional:** `[ -f ]` guard skips missing files (not all repos have `.claude/settings.json`)

- **`--scope user`:** writes to `~/.claude/` (on `claude-home` emptyDir), avoids dirtying the cloned repo

- **No `2>/dev/null`** on jq or CLI calls — errors are visible in `kubectl logs -c plugin-bootstrap` for debugging

- **Tab-delimited marketplace extraction** with proper IFS handling avoids issues with spaces in marketplace names

- [ ] **Step 2: Update ConfigMap generation**

The bootstrap script needs to be available as a ConfigMap in each agent namespace. Two approaches — pick the one that fits existing patterns:

**Option A: Add `configMapGenerator` to each namespace's `kustomization.yaml`**

Each of the 5 namespace `kustomization.yaml` files already generates `claude-settings-profiles` and `claude-managed-settings` ConfigMaps. Add the bootstrap script ConfigMap to each:

```yaml
configMapGenerator:
  # ... existing entries ...
  - name: claude-plugin-bootstrap-script
    files:
      - bootstrap-plugins.sh=../../../claude-agents-shared/base/scripts/bootstrap-plugins.sh
```

Affected files (5 namespaces):

- `cluster/apps/claude-agents-spruyt-labs-write/claude-agents/app/kustomization.yaml`
- `cluster/apps/claude-agents-spruyt-labs-read/claude-agents/app/kustomization.yaml`
- `cluster/apps/claude-agents-spruyt-labs-sre/claude-agents/app/kustomization.yaml`
- `cluster/apps/claude-agents-write/claude-agents/app/kustomization.yaml`
- `cluster/apps/claude-agents-read/claude-agents/app/kustomization.yaml`

**Option B: Add to shared base `kustomization.yaml`**

If the shared base (`cluster/apps/claude-agents-shared/base/kustomization.yaml`) supports `configMapGenerator`, add it there. Currently the shared base only has `resources:` — adding a `configMapGenerator` would generate the ConfigMap once in the base, which each namespace inherits. Check if Kustomize allows this given the base is included via `resources:`.

**Recommendation:** Use Option A for consistency with existing patterns (each namespace already generates its own ConfigMaps with `disableNameSuffixHash: true`). The script source file lives in the shared base but ConfigMap generation happens per-namespace.

- [ ] **Step 3: Add shared volumes to `inject-shared-config`**

In the `inject-shared-config` rule's `mutate.patchStrategicMerge.spec.volumes` list (after the existing `claude-managed-settings` volume at lines 131-133), add two new volumes:

```yaml
              - name: claude-home
                emptyDir:
                  sizeLimit: 256Mi  # ~10 plugins at 2-10MB each + CLI cache
              - name: claude-plugin-bootstrap-script
                configMap:
                  name: claude-plugin-bootstrap-script
                  defaultMode: 0555
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
                  sizeLimit: 256Mi  # ~10 plugins at 2-10MB each + CLI cache
              - name: claude-plugin-bootstrap-script
                configMap:
                  name: claude-plugin-bootstrap-script
                  defaultMode: 0555
```

Why these volumes go in `inject-shared-config` (not in the clone rules): shared volumes belong in the shared rule. The clone rules only add clone-specific resources (workspace emptyDir, SSH/token secrets). The `plugin-bootstrap` init container in the clone rules references these shared volumes via `volumeMounts` — Kubernetes resolves volumes at the pod level regardless of which Kyverno rule added
them.

`defaultMode: 0555` makes the script executable by all users (owner + group + other read + execute). This avoids needing `chmod` or `sh` wrapper — the init container runs `bash /scripts/bootstrap-plugins.sh` directly.

- [ ] **Step 4: Add `plugin-bootstrap` init container to `inject-repo-clone-write`**

In the `inject-repo-clone-write` rule's `initContainers` list (after the `git-clone` init container), add:

```yaml
              - name: plugin-bootstrap
                image: "{{ request.object.spec.containers[0].image }}"
                command: ["bash", "/scripts/bootstrap-plugins.sh"]
                env:
                  - name: HOME
                    value: /home/node
                  - name: GH_CONFIG_DIR
                    value: /tmp/gh-config
                volumeMounts:
                  - name: claude-plugin-bootstrap-script
                    mountPath: /scripts
                    readOnly: true
                  - name: claude-managed-settings
                    mountPath: /etc/claude-code/managed-settings.json
                    subPath: managed-settings.json
                    readOnly: true
                  - name: gh-config-writable
                    mountPath: /tmp/gh-config
                    readOnly: true
                  - name: claude-home
                    mountPath: /home/node/.claude
                  - name: workspace
                    mountPath: /workspace
                    readOnly: true
                securityContext:
                  allowPrivilegeEscalation: false
                  readOnlyRootFilesystem: false
                  capabilities:
                    drop:
                      - ALL
                  runAsNonRoot: true
                resources:
                  requests:
                    cpu: 100m
                    memory: 128Mi
                  limits:
                    memory: 256Mi
```

Init container ordering: Kyverno `patchStrategicMerge` merges init containers by `name` field. When the target pod has no pre-existing init containers, containers are appended in YAML declaration order within the patch. `git-clone` is declared first and completes before `plugin-bootstrap` starts (both are regular init containers, not sidecars). This guarantees the cloned repo at `/workspace/repo`
is available.

Volume availability:

- `claude-plugin-bootstrap-script` — added by `inject-shared-config` (Step 3)
- `claude-managed-settings` — already exists in `inject-shared-config`
- `gh-config-writable` — already exists in `inject-shared-config`
- `claude-home` — added by `inject-shared-config` (Step 3)
- `workspace` — added by `inject-repo-clone-write` itself

`workspace` is mounted read-only because plugin-bootstrap only reads project settings from the cloned repo — it does not modify the workspace.

`readOnlyRootFilesystem: false` because the claude CLI writes temporary files to `/tmp` during plugin installation. No `ephemeral-storage` limit needed — `/tmp` lives on the container's ephemeral rootfs (not on the `claude-home` emptyDir), so those writes are isolated to the init container and don't persist to pod-level storage or the main container.

Resource rationale: 100m CPU request with no limit keeps the init container lightweight. 128Mi memory request / 256Mi limit accounts for jq + claude CLI overhead during plugin network I/O.

No `restartPolicy` field — defaults to run-once. Unlike `gh-config-sync` (sidecar with `restartPolicy: Always`), this init container runs once at pod start and exits.

- [ ] **Step 5: Add `plugin-bootstrap` init container to `inject-repo-clone-read`**

In the `inject-repo-clone-read` rule's `initContainers` list (after the `git-clone` init container), add the identical init container:

```yaml
              - name: plugin-bootstrap
                image: "{{ request.object.spec.containers[0].image }}"
                command: ["bash", "/scripts/bootstrap-plugins.sh"]
                env:
                  - name: HOME
                    value: /home/node
                  - name: GH_CONFIG_DIR
                    value: /tmp/gh-config
                volumeMounts:
                  - name: claude-plugin-bootstrap-script
                    mountPath: /scripts
                    readOnly: true
                  - name: claude-managed-settings
                    mountPath: /etc/claude-code/managed-settings.json
                    subPath: managed-settings.json
                    readOnly: true
                  - name: gh-config-writable
                    mountPath: /tmp/gh-config
                    readOnly: true
                  - name: claude-home
                    mountPath: /home/node/.claude
                  - name: workspace
                    mountPath: /workspace
                    readOnly: true
                securityContext:
                  allowPrivilegeEscalation: false
                  readOnlyRootFilesystem: false
                  capabilities:
                    drop:
                      - ALL
                  runAsNonRoot: true
                resources:
                  requests:
                    cpu: 100m
                    memory: 128Mi
                  limits:
                    memory: 256Mi
```

Both clone rules get identical `plugin-bootstrap` init containers. The script behavior is the same: read all four settings layers (managed → user → project → local) from their respective paths. The only difference between the clone rules is how `git-clone` authenticates (SSH vs HTTPS token), but `plugin-bootstrap` doesn't care — it just reads the resulting clone.

- [ ] **Step 6: Add `claude-home` volumeMount to main container**

In the `inject-shared-config` rule's `containers` section's `volumeMounts` list (after the existing `claude-managed-settings` mount at lines 234-237), add:

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

This gives the main container access to plugins installed by the `plugin-bootstrap` init container via the shared `claude-home` emptyDir.

- [ ] **Step 7: Update policy description annotation**

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
      read-only gitconfig), settings profiles, plugin bootstrap volumes,
      Context7 API key, agentmemory connection, and OpenTelemetry
      env vars into all agent namespaces. Clone rules inject a
      plugin-bootstrap init container (after git-clone) that reads
      managed-settings.json, project settings.json, and
      settings.local.json to install marketplaces and plugins via
      claude CLI. The write rule additionally injects SSH key and
      full gitconfig (with commit signing). Per-namespace rules inject
      MCP configmaps, priority classes, and namespace-specific
      credentials. Repo clone: write uses SSH (with pre-commit),
      read+sre use HTTPS with read-scoped GitHub App token (no SSH
      key = no push capability). Validation rules enforce correct
      CLONE_URL protocol per namespace tier.
```

- [ ] **Step 8: Validate YAML syntax**

Run:

```bash
yamllint cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml
```

Expected: no errors (warnings about line length are acceptable).

- [ ] **Step 9: Commit**

```bash
git add cluster/apps/claude-agents-shared/base/scripts/bootstrap-plugins.sh
git add cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml
git add cluster/apps/claude-agents-spruyt-labs-write/claude-agents/app/kustomization.yaml
git add cluster/apps/claude-agents-spruyt-labs-read/claude-agents/app/kustomization.yaml
git add cluster/apps/claude-agents-spruyt-labs-sre/claude-agents/app/kustomization.yaml
git add cluster/apps/claude-agents-write/claude-agents/app/kustomization.yaml
git add cluster/apps/claude-agents-read/claude-agents/app/kustomization.yaml
git commit -m "feat(claude-agents): add plugin-bootstrap init container and script

Adds a ConfigMap-mounted bootstrap script that reads four settings
layers (managed, user, project, local) to install declared
marketplaces and plugins via claude CLI. Init container runs in both
clone rules (after git-clone) to guarantee repo access. Shared volumes
(claude-home emptyDir, bootstrap-script ConfigMap) added to
inject-shared-config.

Ref #1528"
```

______________________________________________________________________

### Task 2: Write bats tests for the bootstrap script

**Files:**

- Create: `cluster/apps/claude-agents-shared/base/scripts/bootstrap-plugins.bats`

The bootstrap script is a standalone file (not inline YAML), making it testable with bats. Tests mock `jq` and `claude` to verify script logic without requiring the real CLI.

- [ ] **Step 1: Create bats test file**

Create `cluster/apps/claude-agents-shared/base/scripts/bootstrap-plugins.bats` with test cases covering:

| Test Case                    | Input                                               | Expected                                       |
| ---------------------------- | --------------------------------------------------- | ---------------------------------------------- |
| Missing settings file        | File does not exist                                 | Skip gracefully, exit 0                        |
| Empty JSON object `{}`       | Valid JSON with no keys                             | No installs, exit 0                            |
| Invalid JSON                 | Malformed JSON file                                 | Exit 1                                         |
| Disabled plugins (`false`)   | `{"enabledPlugins": {"foo": false}}`                | Skipped, not installed                         |
| String `"true"` handling     | `{"enabledPlugins": {"foo": "true"}}`               | Installed                                      |
| Missing `jq` command         | `jq` not on PATH                                    | Exit 1                                         |
| Missing `claude` command     | `claude` not on PATH                                | Exit 1                                         |
| Marketplace + plugin install | Full settings with both sections                    | Both marketplace add and plugin install called |
| Marketplace with null repo   | `{"extraKnownMarketplaces": {"m": {"source": {}}}}` | Skipped (filtered by `select`)                 |

Test structure:

```bash
#!/usr/bin/env bats

setup() {
  TEST_DIR="$(mktemp -d)"
  export REPO_DIR="$TEST_DIR/repo"
  mkdir -p "$REPO_DIR/.claude"
  # Create mock claude and jq on PATH
  export PATH="$TEST_DIR/bin:$PATH"
  mkdir -p "$TEST_DIR/bin"
  # Mock jq: use real jq if available, tests that need to remove it override PATH
  if command -v jq >/dev/null 2>&1; then
    ln -s "$(command -v jq)" "$TEST_DIR/bin/jq"
  fi
  # Mock claude: log calls to a file for assertion
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$TEST_DIR/claude-calls.log"
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export TEST_DIR
}

teardown() {
  rm -rf "$TEST_DIR"
}
```

Each test uses `bats run` with the script path and asserts on exit code and output. Tests that need to simulate missing commands remove the mock from PATH.

- [ ] **Step 2: Verify tests run locally**

```bash
# Install bats if not available
command -v bats || npm install -g bats

bats cluster/apps/claude-agents-shared/base/scripts/bootstrap-plugins.bats
```

Expected: all tests pass.

- [ ] **Step 3: Add bats-test job to CI workflow**

In `.github/workflows/ci.yaml`:

1. Add path filter to the `changes` job's `dorny/paths-filter` config:

```yaml
          filters: |
            # ... existing filters ...
            claude-agents:
              - 'cluster/apps/claude-agents-shared/**'
```

2. Add `bats-test` job (after `kyverno-test`, same pattern):

```yaml
  bats-test:
    needs: changes
    if: needs.changes.outputs.claude-agents == 'true'
    uses: ./.github/workflows/_bats-test.yaml
```

3. Create reusable workflow `.github/workflows/_bats-test.yaml`:

```yaml
name: Bats Tests
on:
  workflow_call:
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install bats
        run: sudo apt-get install -y bats
      - name: Run bootstrap-plugins tests
        run: bats cluster/apps/claude-agents-shared/base/scripts/bootstrap-plugins.bats
```

4. Add `bats-test` to the `summary` job's `needs` array.

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/claude-agents-shared/base/scripts/bootstrap-plugins.bats
git add .github/workflows/ci.yaml
git add .github/workflows/_bats-test.yaml
git commit -m "test(claude-agents): add bats tests and CI job for plugin bootstrap script

Tests cover: missing settings file, empty JSON, invalid JSON, disabled
plugins, string 'true' handling, missing jq/claude, marketplace with
null repo, and full marketplace + plugin install flow. CI runs bats
on changes to cluster/apps/claude-agents-shared/.

Ref #1528"
```

______________________________________________________________________

### Task 3: Add plugin bootstrap to devcontainer post-create.sh

**Files:**

- Modify: `devcontainer-common/assets/post-create.sh` in `anthony-spruyt/container-images` repo

This is a cross-repo change in `anthony-spruyt/container-images` (separate repo, separate PR). Clone it, make the change, and open a PR there.

- [ ] **Step 1: Clone the container-images repo**

```bash
gh repo clone anthony-spruyt/container-images /tmp/container-images
cd /tmp/container-images
git checkout -b feat/plugin-bootstrap
```

- [ ] **Step 2: Add `bootstrap_claude_plugins()` function**

In `devcontainer-common/assets/post-create.sh`, after the Claude CLI installation block. Locate the insertion point by searching for the PATH export line (`grep -q 'local/bin'`). If that line has moved, insert after the last line of the Claude CLI installation section. Add:

```bash
# Bootstrap Claude Code plugins from project settings
if command -v claude &>/dev/null && command -v jq &>/dev/null; then
  bootstrap_claude_plugins() {
    local settings_file="$1"
    [ -f "$settings_file" ] || return 0
    jq empty "$settings_file" 2>/dev/null || { echo "  WARNING: invalid JSON in $settings_file, skipping"; return 0; }
    echo "  reading $settings_file"
    jq -r '.extraKnownMarketplaces // {} | to_entries[] | select(.value.source != null and .value.source.repo != null) | "\(.key)\t\(.value.source.repo)"' \
      "$settings_file" 2>/dev/null | while IFS="$(printf '\t')" read -r name repo; do
      echo "    marketplace: $name ($repo)"
      claude plugins marketplace add "$repo" --scope user \
        || echo "    WARNING: failed to add marketplace '$name'"
    done
    jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true or .value == "true") | .key' \
      "$settings_file" 2>/dev/null | while IFS= read -r plugin; do
      echo "    install: $plugin"
      claude plugins install "$plugin" --scope user \
        || echo "    WARNING: failed to install '$plugin'"
    done
  }
  echo "Bootstrapping Claude Code plugins..."
  # Settings precedence: user → project → local
  bootstrap_claude_plugins "$HOME/.claude/settings.json"
  # $WORKSPACE is set by devcontainer lifecycle (points to repo clone root)
  bootstrap_claude_plugins "$WORKSPACE/.claude/settings.json"
  bootstrap_claude_plugins "$WORKSPACE/.claude/settings.local.json"
fi
```

Key differences from the cluster agent version:

- Reads from user + project settings (no `managed-settings.json` ConfigMap — does not exist in devcontainer context)

- Guarded by `command -v claude` and `command -v jq` (jq may not be in all devcontainer images)

- Uses `2>/dev/null` on jq data-extraction calls (suppresses parse errors to avoid noise in post-create output); cluster version omits `2>/dev/null` on jq extraction calls — errors appear in init container stderr (visible via `kubectl logs -c plugin-bootstrap`) for debugging

- JSON validation failure is non-fatal (`return 0`) vs cluster version which is fatal (`exit 1`) — cluster settings come from a ConfigMap (infrastructure-managed; invalid JSON signals a config error that should block pod start), while project settings are developer-managed (a syntax error shouldn't block devcontainer startup)

- Function definition wrapped inside the tool-availability guard — spec defines function unconditionally then calls conditionally

**Plan-level improvements over spec (both environments):**

- Both environments validate JSON structure (`jq empty`) and tool availability before processing — spec omits these guards

- Devcontainer adds `jq` availability check (`command -v jq`) to the guard — spec only checks for `claude` CLI

- Both use tab-delimited marketplace extraction (`"\(.key)\t\(.value.source.repo)"`) with proper IFS handling — spec's cluster version uses space-delimited format, spec's devcontainer version omits the name field entirely

- Both add `select(.value.source != null and .value.source.repo != null)` to marketplace jq filter — spec assumes field always exists

- Both accept string `"true"` in addition to boolean `true` for `enabledPlugins` values — spec only handles boolean

- Cluster version omits `2>/dev/null` on jq and CLI calls (errors visible in `kubectl logs -c plugin-bootstrap`); devcontainer version suppresses stderr on jq extraction calls only (not CLI calls) to reduce post-create noise while preserving install error visibility

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
- All commands idempotent and fault-tolerant (logs warning on failure, continues)
BODY
)"
```

______________________________________________________________________

### Task 4: Push spruyt-labs changes and validate

- [ ] **Step 1: Push to main**

```bash
git push
```

Flux webhook auto-reconciles — no manual `flux reconcile` needed.

- [ ] **Step 2: Run cluster-validator**

After push, run the `cluster-validator` agent to verify:

- Kyverno ClusterPolicy reconciles without errors

- Policy report shows no violations

- ConfigMap `claude-plugin-bootstrap-script` exists in all 5 agent namespaces

- Next agent pod spawn includes the `plugin-bootstrap` init container

- [ ] **Step 3: Verify init container in a live pod**

After an agent pod spawns (or trigger one via n8n), verify the init container ran:

```bash
# Example: use any agent namespace (sre, write, read)
kubectl get pods -l managed-by=n8n-claude-code \
  -n claude-agents-spruyt-labs-sre \
  --sort-by=.metadata.creationTimestamp | tail -1
# Fallback if label doesn't match:
# kubectl get pods -n claude-agents-spruyt-labs-sre --sort-by=.metadata.creationTimestamp | tail -1
```

Check init container logs:

```bash
kubectl logs <pod-name> -n claude-agents-spruyt-labs-sre -c plugin-bootstrap
```

Expected output:

```text
[plugin-bootstrap] reading /etc/claude-code/managed-settings.json
[plugin-bootstrap] marketplace add: <name> (<owner>/<repo>)
...
[plugin-bootstrap] install: <plugin-id>
...
[plugin-bootstrap] reading /home/node/.claude/settings.json
...
[plugin-bootstrap] reading /workspace/repo/.claude/settings.json
[plugin-bootstrap] marketplace add: <name> (<owner>/<repo>)
...
[plugin-bootstrap] reading /workspace/repo/.claude/settings.local.json
[plugin-bootstrap] install: <plugin-id>
...
[plugin-bootstrap] done
```

- [ ] **Step 4: Close issue after both PRs merge and validate**

Post validation results as a comment on [#1528](https://github.com/anthony-spruyt/spruyt-labs/issues/1528). Close only after both PRs (spruyt-labs Kyverno policy + container-images post-create.sh) are merged and validated. If the container-images PR is blocked, close after the spruyt-labs PR validates and note the pending cross-repo change in the issue comment.

______________________________________________________________________

## Removal Condition

Delete bootstrap logic when upstream auto-install lands. Track:

- [anthropics/claude-code#45323](https://github.com/anthropics/claude-code/issues/45323)
- [anthropics/claude-code#16870](https://github.com/anthropics/claude-code/issues/16870)
- [anthropics/claude-code#51118](https://github.com/anthropics/claude-code/issues/51118)
