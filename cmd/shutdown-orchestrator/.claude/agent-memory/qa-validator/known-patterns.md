---
name: qa-validator-known-patterns
description: Patterns observed during QA validation runs for shutdown-orchestrator
type: reference
---

# Known Patterns

| Pattern                                                          | Category     | Count | Last Seen  | Added      | Notes                                                                                                 |
| ---------------------------------------------------------------- | ------------ | ----- | ---------- | ---------- | ----------------------------------------------------------------------------------------------------- |
| Go project skips K8s schema/dry-run checks                       | skip-logic   | 5     | 2026-03-23 | 2026-03-23 | Go code changes don't need kubectl dry-run or kustomize build (but RBAC yaml still needs it)          |
| Dockerfile base image version must match go.mod                  | validation   | 1     | 2026-03-23 | 2026-03-23 | Verify Docker Hub tag exists when Dockerfile pins a specific Go patch version                         |
| defer inside for-loop in monitor.go shutdown path                | code-pattern | 2     | 2026-03-23 | 2026-03-23 | Fixed: now calls shutdownCancel() explicitly instead of defer inside loop                             |
| t.Setenv("key", "") equivalent to os.Unsetenv for envOrDefault   | code-pattern | 2     | 2026-03-23 | 2026-03-23 | Fixed: now calls os.Unsetenv in addition to t.Setenv("", "") for proper clearing                      |
| Phase timeout budget validation in Config.Validate               | code-pattern | 3     | 2026-03-23 | 2026-03-23 | Validates sum of phase timeouts does not exceed UPS budget minus shutdown delay                       |
| pullPolicy Always required for latest tag                        | validation   | 1     | 2026-03-23 | 2026-03-23 | Without Always, K8s caches latest and won't pull new builds                                           |
| nil error appending to error slice with errors.Join              | code-pattern | 1     | 2026-03-23 | 2026-03-23 | append(errs, possiblyNilErr) adds nil to slice; errors.Join ignores nils but len(errs) misleads       |
| Persistent TCP client lazy connect pattern                       | code-pattern | 2     | 2026-03-23 | 2026-03-23 | NewNUTClient stores config only; connection deferred to first GetStatus call; scanner stored as field |
| values.yaml env vars must match config.go env var names+defaults | validation   | 2     | 2026-03-23 | 2026-03-23 | Cross-check values.yaml env entries against envOrDefault/envIntOrDefault calls in config.go           |
| hookify local config must not be committed                       | validation   | 5     | 2026-03-23 | 2026-03-23 | .claude/hookify.\*.local.md files are local dev settings, should never be staged                      |
| RBAC verbs must match actual code usage                          | validation   | 1     | 2026-03-23 | 2026-03-23 | Grep codebase for actual API calls before approving RBAC verb changes (e.g., nodes patch/update)      |
| time.NewTimer replaces time.After in select                      | code-pattern | 1     | 2026-03-23 | 2026-03-23 | time.After leaks goroutine if ctx cancels before timer fires; NewTimer + Stop() is correct            |
| README env var table must list all config.go env vars            | validation   | 1     | 2026-03-23 | 2026-03-23 | Cross-check README env var table against LoadConfig() to ensure completeness                          |
