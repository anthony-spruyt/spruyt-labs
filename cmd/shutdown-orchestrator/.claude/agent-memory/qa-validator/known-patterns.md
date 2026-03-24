---
name: qa-validator-known-patterns
description: Observed patterns from QA validation runs for shutdown-orchestrator
type: reference
---

# QA Validator Known Patterns

| Pattern                                                                                  | Category     | Count | Last Seen  | Added      | Notes                                                                                 |
| ---------------------------------------------------------------------------------------- | ------------ | ----- | ---------- | ---------- | ------------------------------------------------------------------------------------- |
| Go files used 2-space indent instead of tabs                                             | linting      | 1     | 2026-03-24 | 2026-03-24 | All Go files had spaces; golangci-lint/gofmt auto-fixed to tabs                       |
| MegaLinter GO_GOLANGCI_LINT needs wrapper script for monorepo                            | config quirk | 1     | 2026-03-24 | 2026-03-24 | golangci-lint must cd into Go module dir; PRE_COMMANDS + CLI_EXECUTABLE pattern works |
| Custom GHCR MegaLinter image requires MEGALINTER_FLAVOR=all                              | config quirk | 1     | 2026-03-24 | 2026-03-24 | Without this, MegaLinter rejects custom images during flavor validation               |
| gocritic appendAssign flags `allErrs := append(slice1, slice2...)` as potential mutation | lint finding | 1     | 2026-03-24 | 2026-03-24 | Fix: allocate new slice with make() first, then append both                           |
| gocritic exitAfterDefer flags os.Exit() in function with defers                          | lint finding | 1     | 2026-03-24 | 2026-03-24 | Fix: extract to run() int, call os.Exit(run()) from main()                            |
| gocritic ifElseChain flags if/else if/else chains                                        | lint finding | 1     | 2026-03-24 | 2026-03-24 | Fix: convert to switch statement                                                      |
