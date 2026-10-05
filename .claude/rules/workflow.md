# Workflow

## Commits

**After push:** Flux webhooks auto-reconcile - no manual `flux reconcile` needed.

## Linting Layers

| Layer            | When          | Speed   | Purpose                                                          |
| ---------------- | ------------- | ------- | ---------------------------------------------------------------- |
| **qa-validator** | Before commit | Minutes | Comprehensive MegaLinter + schema/docs verification (shift-left) |
| **Pre-commit**   | At commit     | Seconds | Fast guards (yamllint, gitleaks, markdownlint, shellcheck)       |
| **CI**           | Push/PR       | Minutes | Safety net, PR gate                                              |

> **Note:** qa-validator runs MegaLinter. No need to run `task dev-env:lint` separately if qa-validator passed.
