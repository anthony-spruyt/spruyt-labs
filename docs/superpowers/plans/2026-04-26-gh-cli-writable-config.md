# Fix gh CLI Writable Config — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix `gh` CLI in Claude agent pods by making `GH_CONFIG_DIR` writable while preserving live token rotation from the secret volume.

**Architecture:** Add an `emptyDir` volume for writable gh config state, move the secret mount to a new path, and use an init container to symlink `hosts.yml` from the secret into the emptyDir. `gh` reads auth via symlink (follows through to live secret), writes state files to writable emptyDir.

**Tech Stack:** Kyverno ClusterPolicy (patchStrategicMerge), Kubernetes volumes (secret + emptyDir), busybox init container.

**Spec:** `docs/superpowers/specs/2026-04-26-gh-cli-writable-config-design.md` **Issue:** [#1048](https://github.com/anthony-spruyt/spruyt-labs/issues/1048)

______________________________________________________________________

## File Map

| File                                                                | Action | Responsibility                                         |
| ------------------------------------------------------------------- | ------ | ------------------------------------------------------ |
| `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml` | Modify | All changes — volumes, init container, env var, mounts |

All changes are within the `inject-shared-config` rule (lines 26–111 of the existing file).

______________________________________________________________________

### Task 1: Add emptyDir volume and move secret mount path

**Files:**

- Modify: `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml:42-58` (volumes block)

- [ ] **Step 1: Add `gh-config-writable` emptyDir volume to the volumes list**

In the `inject-shared-config` rule's `spec.volumes` block, add a new volume after `github-gh-config`:

```yaml
              - name: gh-config-writable
                emptyDir: {}
```

The volumes block should now read:

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
              - name: github-ssh-key
                secret:
                  secretName: github-bot-ssh-key
                  defaultMode: 0444
              - name: github-gitconfig
                configMap:
                  name: github-bot-gitconfig
              - name: claude-settings-profiles
                configMap:
                  name: claude-settings-profiles
```

- [ ] **Step 2: Verify YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml'))"` Expected: No output (valid YAML)

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml
git commit -m "fix(kyverno): add emptyDir volume for writable gh config

Ref #1048"
```

______________________________________________________________________

### Task 2: Add gh-config-init init container

**Files:**

- Modify: `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml` (inject-shared-config rule, add initContainers block)

- [ ] **Step 1: Add initContainers block to the inject-shared-config rule's mutate.patchStrategicMerge.spec**

Insert after the `volumes` block and before the `containers` block:

```yaml
            initContainers:
              - name: gh-config-init
                image: "busybox:1.37.0@sha256:1487d0af5f52b4ba31c7e465126ee2123fe3f2305d638e7827681e7cf6c83d5e"
                command: ["sh", "-c"]
                args:
                  - ln -s /etc/gh-secret/hosts.yml /tmp/gh-config/hosts.yml
                volumeMounts:
                  - name: github-gh-config
                    mountPath: /etc/gh-secret
                    readOnly: true
                  - name: gh-config-writable
                    mountPath: /tmp/gh-config
```

- [ ] **Step 2: Verify YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml'))"` Expected: No output (valid YAML)

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml
git commit -m "fix(kyverno): add gh-config-init init container for symlink setup

Ref #1048"
```

______________________________________________________________________

### Task 3: Update GH_CONFIG_DIR env var

**Files:**

- Modify: `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml:62-63` (GH_CONFIG_DIR entry)

- [ ] **Step 1: Change GH_CONFIG_DIR value from `/etc/gh` to `/tmp/gh-config`**

Find in the `containers` env block:

```yaml
                  - name: GH_CONFIG_DIR
                    value: /etc/gh
```

Replace with:

```yaml
                  - name: GH_CONFIG_DIR
                    value: /tmp/gh-config
```

- [ ] **Step 2: Verify YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml'))"` Expected: No output (valid YAML)

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml
git commit -m "fix(kyverno): update GH_CONFIG_DIR to writable emptyDir path

Ref #1048"
```

______________________________________________________________________

### Task 4: Update main container volumeMounts

**Files:**

- Modify: `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml:100-102` (github-gh-config volumeMount entry)

- [ ] **Step 1: Change github-gh-config mountPath from `/etc/gh` to `/etc/gh-secret`**

Find in the `containers` volumeMounts block:

```yaml
                  - name: github-gh-config
                    mountPath: /etc/gh
                    readOnly: true
```

Replace with:

```yaml
                  - name: github-gh-config
                    mountPath: /etc/gh-secret
                    readOnly: true
```

- [ ] **Step 2: Add gh-config-writable mount to main container**

Add after the `github-gh-config` mount:

```yaml
                  - name: gh-config-writable
                    mountPath: /tmp/gh-config
```

The full volumeMounts block should now read:

```yaml
                volumeMounts:
                  - name: github-gh-config
                    mountPath: /etc/gh-secret
                    readOnly: true
                  - name: gh-config-writable
                    mountPath: /tmp/gh-config
                  - name: github-ssh-key
                    mountPath: /etc/git-ssh
                    readOnly: true
                  - name: github-gitconfig
                    mountPath: /etc/git-config
                    readOnly: true
                  - name: claude-settings-profiles
                    mountPath: /etc/claude/settings
                    readOnly: true
```

- [ ] **Step 3: Verify YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml'))"` Expected: No output (valid YAML)

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml
git commit -m "fix(kyverno): mount writable gh config dir on main container

Ref #1048"
```

______________________________________________________________________

### Task 5: Final validation

- [ ] **Step 1: Run kustomize build to verify Kyverno policy renders correctly**

Run: `kubectl kustomize cluster/apps/kyverno/policies/app/ 2>&1 | head -20` Expected: Valid YAML output starting with the ClusterPolicy resource

- [ ] **Step 2: Verify no other references to `/etc/gh` remain in the file**

Run: `grep -n '/etc/gh' cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml | grep -v '/etc/gh-' || echo "clean"` Expected: `clean` — all references should now be `/etc/gh-secret` or `/tmp/gh-config`

- [ ] **Step 3: Verify the complete inject-shared-config rule structure**

Read the full file and confirm:

1. `volumes` has both `github-gh-config` (secret) and `gh-config-writable` (emptyDir)
1. `initContainers` has `gh-config-init` with mounts to both volumes
1. `containers` env has `GH_CONFIG_DIR=/tmp/gh-config`
1. `containers` volumeMounts has `github-gh-config` at `/etc/gh-secret` and `gh-config-writable` at `/tmp/gh-config`
