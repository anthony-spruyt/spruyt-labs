# Go Lint Unification Design

**Issue:** [#769](https://github.com/anthony-spruyt/spruyt-labs/issues/769)
**Date:** 2026-03-25

## Problem

The repo has two Go modules:

- `cmd/shutdown-orchestrator` — Go 1.25.3, linted by MegaLinter
- `cluster/apps/traefik/traefik/app/plugins/traefik-api-key-auth` — Go 1.26.1, not linted

The MegaLinter golangci-lint wrapper hardcodes `cd cmd/shutdown-orchestrator`, so the traefik plugin is excluded from linting. The two modules also use different Go versions.

## Goals

1. Both modules use the same Go version (latest stable: 1.26.1)
2. Both modules are linted by MegaLinter's golangci-lint
3. New Go modules added in the future are automatically discovered and linted

## Design

### 1. Upgrade shutdown-orchestrator to Go 1.26.1

Update `cmd/shutdown-orchestrator/go.mod` from `go 1.25.3` to `go 1.26.1`. Run `go mod tidy` to update dependencies.

### 2. Multi-module MegaLinter wrapper

MegaLinter's golangci-lint integration has two phases:

1. **`GO_GOLANGCI_LINT_PRE_COMMANDS`** — runs once at startup (setup)
2. **`GO_GOLANGCI_LINT_CLI_EXECUTABLE`** — invoked by MegaLinter per discovered `.go` file

The current wrapper does setup in phase 1 (creates the script, downloads deps) and linting in phase 2 (the script `cd`s into the module and runs golangci-lint). The new design keeps this separation.

**Phase 1 (pre-command):** Discovers all `go.mod` files under `$WS`, runs `go mod download` for each module, then writes the wrapper script to `/tmp/golangci-lint-wrapper.sh`.

**Phase 2 (wrapper script):** When MegaLinter invokes the wrapper per `.go` file, the wrapper:

1. Determines which module the file belongs to (walks parent directories for `go.mod`)
2. Runs `golangci-lint run ./...` from that module's root with `--config "$WS/.golangci.yml"` to ensure the shared config is always used regardless of working directory
3. Caches which modules have already been linted to avoid re-running for every `.go` file in the same module
4. Returns the exit code from golangci-lint

Directory exclusions in the `find` command: `vendor/`, `.output/`, `clusterconfig/`, `legacy/`, `talos/` — consistent with `EXCLUDED_DIRECTORIES` in `.mega-linter.yml`.

Environment variables carried forward:
- `GOMODCACHE=/tmp/gomod`
- `GOPATH=/tmp/gopath`

The `GO_GOLANGCI_LINT_CONFIG_FILE` setting is kept in `.mega-linter.yml` for documentation but the wrapper explicitly passes `--config` to avoid relying on golangci-lint's auto-discovery from subdirectories.

### 3. Fix lint findings in the traefik plugin

The plugin has never been linted. Any findings from govet, staticcheck, gocritic, ineffassign, or unused will be fixed.

### 4. Update issue #769

Rewrite the issue body to reflect the actual scope (Go version alignment + multi-module lint coverage).

## Files Changed

| File | Change |
| ------ | -------- |
| `cmd/shutdown-orchestrator/go.mod` | `go 1.25.3` → `go 1.26.1` |
| `cmd/shutdown-orchestrator/go.sum` | Updated by `go mod tidy` |
| `.mega-linter.yml` | Rewrite `GO_GOLANGCI_LINT_PRE_COMMANDS` wrapper |
| `cluster/apps/traefik/traefik/app/plugins/traefik-api-key-auth/plugin.go` | Fix lint findings (if any) |

## Risks

- **Yaegi compatibility:** The traefik plugin runs under Yaegi (Traefik's Go interpreter). Yaegi supports a subset of Go — lint fixes must not introduce stdlib features Yaegi doesn't support. The plugin currently uses only basic stdlib packages (net/http, crypto/subtle, encoding/json, etc.) which are well-supported.
- **Go 1.26.1 upgrade for shutdown-orchestrator:** Minor version bump from 1.25.3. Dependencies may need updating via `go mod tidy`. Low risk — no breaking changes expected between 1.25 and 1.26.
- **MegaLinter wrapper failure isolation:** MegaLinter invokes the wrapper per `.go` file, so each module is linted independently. However, MegaLinter may stop invoking the wrapper after the first non-zero exit, meaning a failure in one module could prevent linting of others in the same run. For a two-module repo this is acceptable.
