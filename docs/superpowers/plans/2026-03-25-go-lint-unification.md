# Go Lint Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align both Go modules to the latest Go version and extend MegaLinter to automatically discover and lint all Go modules.

**Architecture:** Replace the hardcoded single-module MegaLinter wrapper with a multi-module discovery wrapper. Upgrade shutdown-orchestrator from Go 1.25.3 to 1.26.1 to match the traefik plugin.

**Tech Stack:** Go 1.26.1, golangci-lint v2, MegaLinter

**Spec:** `docs/superpowers/specs/2026-03-25-go-lint-unification-design.md`
**Issue:** [#769](https://github.com/anthony-spruyt/spruyt-labs/issues/769)

---

## File Structure

| File | Action | Purpose |
| ------ | ------ | ------ |
| `cmd/shutdown-orchestrator/go.mod` | Modify | Bump `go 1.25.3` to `go 1.26.1` |
| `cmd/shutdown-orchestrator/go.sum` | Modify | Updated by `go mod tidy` |
| `scripts/golangci-lint-multi.sh` | Create | Multi-module wrapper script |
| `.mega-linter.yml` | Modify | Rewrite `GO_GOLANGCI_LINT_PRE_COMMANDS` to use new wrapper |

**Skipped from spec:** Section 3 (fix traefik plugin lint findings) — verified unnecessary.
Both modules pass golangci-lint v2 with 0 issues locally. No fixes needed.

---

### Task 1: Update issue #769

Update the GitHub issue to reflect the actual scope.

- [ ] **Step 1: Update issue body**

```bash
gh issue edit 769 --repo anthony-spruyt/spruyt-labs --title "chore(go): align Go versions and extend MegaLinter to all modules" --body "$(cat <<'ISSUE_EOF'
## Summary

Align both Go modules to Go 1.26.1 (latest stable) and extend MegaLinter's golangci-lint wrapper to automatically discover and lint all Go modules in the repo.

## Motivation

The shutdown-orchestrator uses Go 1.25.3 while the traefik-api-key-auth plugin uses Go 1.26.1. The MegaLinter wrapper only covers shutdown-orchestrator. Both modules should use the same Go version and both should be linted.

## Chore Type

Dependency update

## Affected Area

Tooling (.taskfiles/, scripts)

## Changes

- Upgrade `cmd/shutdown-orchestrator/go.mod` from Go 1.25.3 to 1.26.1
- Rewrite MegaLinter golangci-lint wrapper to discover all `go.mod` files automatically
- Verify both modules pass linting
ISSUE_EOF
)"
```

---

### Task 2: Upgrade shutdown-orchestrator to Go 1.26.1

**Files:**

- Modify: `cmd/shutdown-orchestrator/go.mod:3` — change `go 1.25.3` to `go 1.26.1`
- Modify: `cmd/shutdown-orchestrator/go.sum` — updated by `go mod tidy`

- [ ] **Step 1: Update go.mod version**

In `cmd/shutdown-orchestrator/go.mod`, change line 3:

```go
go 1.26.1
```

- [ ] **Step 2: Run go mod tidy**

```bash
cd /workspaces/spruyt-labs/cmd/shutdown-orchestrator && go mod tidy
```

Expected: Updates `go.sum` with any dependency changes. No errors.

- [ ] **Step 3: Verify lint still passes**

```bash
cd /workspaces/spruyt-labs/cmd/shutdown-orchestrator && golangci-lint run --config /workspaces/spruyt-labs/.golangci.yml ./...
```

Expected: `0 issues.` (or no output, exit code 0)

- [ ] **Step 4: Verify build**

```bash
cd /workspaces/spruyt-labs/cmd/shutdown-orchestrator && go build ./...
```

Expected: exit code 0, no errors.

- [ ] **Step 5: Commit**

```bash
git add cmd/shutdown-orchestrator/go.mod cmd/shutdown-orchestrator/go.sum
git commit -m "chore(shutdown-orchestrator): upgrade Go 1.25.3 to 1.26.1

Ref #769"
```

---

### Task 3: Rewrite MegaLinter multi-module wrapper

**Files:**

- Modify: `.mega-linter.yml:15-20` — rewrite `GO_GOLANGCI_LINT_PRE_COMMANDS` and keep `GO_GOLANGCI_LINT_CLI_EXECUTABLE`

The wrapper has two phases per the spec:

**Phase 1 (pre-command):** Discovers all `go.mod` files, runs `go mod download` for each, writes the wrapper script via `printf` (avoids heredoc-inside-YAML-block-scalar indentation issues).

**Phase 2 (wrapper script):** MegaLinter invokes the wrapper per `.go` file. The wrapper finds which module the file belongs to, checks if that module has already been linted (via a cache file), and if not, runs `golangci-lint run ./...` with `--config` pointing to the repo root config. Subsequent `.go` files in the same module are no-ops (exit 0).

**Failure isolation note:** MegaLinter may stop invoking the wrapper after the first non-zero
exit code. This means if module A fails, module B may not be linted in that run. This is a
MegaLinter behavioral constraint we cannot control — the wrapper correctly caches and returns
per-module results, but full isolation would require always returning 0 and reporting failures
through a different mechanism. For a two-module repo this is acceptable.

- [ ] **Step 1: Write the wrapper script file**

Create the `scripts/` directory if it doesn't exist (`mkdir -p scripts`), then create
`scripts/golangci-lint-multi.sh` with the wrapper logic. This avoids the
heredoc-inside-YAML problem by keeping the script as a standalone file that gets copied
into place by the pre-command.

```bash
#!/bin/sh
# Multi-module golangci-lint wrapper for MegaLinter.
# MegaLinter invokes this once per .go file. The wrapper finds the
# enclosing Go module, lints it once, and caches the result so
# subsequent .go files in the same module are no-ops.
set -eu
export GOMODCACHE=/tmp/gomod GOPATH=/tmp/gopath
WS="${DEFAULT_WORKSPACE:-/tmp/lint}"
CACHE_DIR="/tmp/golangci-lint-done"
mkdir -p "$CACHE_DIR"

# Find the module root for the given .go file
target="$1"
if [ -z "$target" ]; then
  exit 0
fi
dir="$(cd "$(dirname "$target")" 2>/dev/null && pwd)"
modroot=""
while [ "$dir" != "/" ] && [ -n "$dir" ]; do
  if [ -f "$dir/go.mod" ]; then
    modroot="$dir"
    break
  fi
  dir="$(dirname "$dir")"
done
if [ -z "$modroot" ]; then
  echo "No go.mod found for $target, skipping"
  exit 0
fi

# Cache key: hash of module path
cache_key="$(echo "$modroot" | md5sum | cut -d' ' -f1)"
if [ -f "$CACHE_DIR/$cache_key" ]; then
  exit "$(cat "$CACHE_DIR/$cache_key")"
fi

# Run golangci-lint for this module
echo "golangci-lint: $modroot"
cd "$modroot" || exit 1
golangci-lint run --config "$WS/.golangci.yml" ./...
rc=$?
echo "$rc" > "$CACHE_DIR/$cache_key"
exit $rc
```

- [ ] **Step 2: Write the new MegaLinter config**

Replace lines 15-20 in `.mega-linter.yml` with:

```yaml
GO_GOLANGCI_LINT_PRE_COMMANDS:
  - command: "export GOMODCACHE=/tmp/gomod GOPATH=/tmp/gopath && find . -name go.mod -not -path '*/vendor/*' -not -path '*/.output/*' -not -path '*/clusterconfig/*' -not -path '*/legacy/*' -not -path '*/talos/*' -not -path '*/.claude/*' -not -path '*/.git/*' -not -path '*/plans/*' | while read -r modfile; do moddir=\"$(dirname \"$modfile\")\"; echo \"go mod download: $moddir\"; (cd \"$moddir\" && go mod download) || true; done && cp scripts/golangci-lint-multi.sh /tmp/golangci-lint-wrapper.sh && chmod +x /tmp/golangci-lint-wrapper.sh"
    cwd: "workspace"
GO_GOLANGCI_LINT_CLI_EXECUTABLE:
  - "/tmp/golangci-lint-wrapper.sh"
GO_GOLANGCI_LINT_CONFIG_FILE: .golangci.yml
```

Key design points:

- Pre-command stays as a single-line string (matches existing pattern, avoids YAML block scalar issues)
- Wrapper script is a standalone file in `scripts/` — easier to read, test, and maintain
- `find` exclusions cover `EXCLUDED_DIRECTORIES` from both `.mega-linter.yml` and `.mega-linter-base.yml`, plus `vendor/` as a standard Go convention
- Wrapper walks parent dirs from the `.go` file to find its `go.mod`
- Cache file per module (md5 of path) prevents re-running for every `.go` file in the same module
- `--config "$WS/.golangci.yml"` ensures the shared config is always used
- Failed `go mod download` is non-fatal (`|| true`) — the lint step will catch real errors

- [ ] **Step 3: Verify YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.mega-linter.yml'))"
```

Expected: no output, exit code 0.

- [ ] **Step 4: Test wrapper logic locally**

Run the pre-command setup, then invoke the wrapper with both modules:

```bash
# Setup (simulates what MegaLinter pre-command does)
export DEFAULT_WORKSPACE=/workspaces/spruyt-labs
export GOMODCACHE=/tmp/gomod GOPATH=/tmp/gopath
rm -rf /tmp/golangci-lint-done
cp /workspaces/spruyt-labs/scripts/golangci-lint-multi.sh /tmp/golangci-lint-wrapper.sh
chmod +x /tmp/golangci-lint-wrapper.sh

# Test shutdown-orchestrator module
/tmp/golangci-lint-wrapper.sh /workspaces/spruyt-labs/cmd/shutdown-orchestrator/main.go
echo "shutdown-orchestrator exit: $?"

# Test traefik plugin module
/tmp/golangci-lint-wrapper.sh /workspaces/spruyt-labs/cluster/apps/traefik/traefik/app/plugins/traefik-api-key-auth/plugin.go
echo "traefik-plugin exit: $?"

# Test cache (should be instant, reuses cached result)
/tmp/golangci-lint-wrapper.sh /workspaces/spruyt-labs/cmd/shutdown-orchestrator/main.go
echo "cached exit: $?"
```

Expected: all three exit 0. The third invocation should produce no golangci-lint output (cache hit).

- [ ] **Step 5: Commit**

```bash
git add scripts/golangci-lint-multi.sh .mega-linter.yml
git commit -m "chore(megalinter): multi-module golangci-lint wrapper

Rewrite the Go linting wrapper to auto-discover all go.mod files
instead of hardcoding cmd/shutdown-orchestrator. Each module is
linted once with the shared .golangci.yml config.

Ref #769"
```

---

### Task 4: Run qa-validator

- [ ] **Step 1: Run qa-validator agent**

Run the `qa-validator` agent to validate all changes before final commit/push.

Expected: APPROVED with no blocking issues.

---
