---
name: qa-validator-known-patterns
description: Patterns observed during QA validation runs for shutdown-orchestrator
type: reference
---

# Known Patterns

| Pattern                                                        | Category     | Count | Last Seen  | Added      | Notes                                                                            |
| -------------------------------------------------------------- | ------------ | ----- | ---------- | ---------- | -------------------------------------------------------------------------------- |
| Go project skips K8s schema/dry-run checks                     | skip-logic   | 1     | 2026-03-23 | 2026-03-23 | Go code changes don't need kubectl dry-run or kustomize build                    |
| Dockerfile base image version must match go.mod                | validation   | 1     | 2026-03-23 | 2026-03-23 | Verify Docker Hub tag exists when Dockerfile pins a specific Go patch version    |
| defer inside for-loop in monitor.go shutdown path              | code-pattern | 2     | 2026-03-23 | 2026-03-23 | Fixed: now calls shutdownCancel() explicitly instead of defer inside loop        |
| t.Setenv("key", "") equivalent to os.Unsetenv for envOrDefault | code-pattern | 2     | 2026-03-23 | 2026-03-23 | Fixed: now calls os.Unsetenv in addition to t.Setenv("", "") for proper clearing |
| Phase timeout budget validation in Config.Validate             | code-pattern | 1     | 2026-03-23 | 2026-03-23 | Validates sum of phase timeouts does not exceed UPS budget minus shutdown delay  |
