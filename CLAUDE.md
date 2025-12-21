# CLAUDE.md

Talos Linux homelab GitOps repository.

## Rules

See [docs/rules/core_rules.md](docs/rules/core_rules.md) for constraints, conventions, and workflow.

## Documentation

- **Architecture**: [README.md](README.md)
- **Rules**: [docs/rules/](docs/rules/)
- **Runbooks**: [docs/](docs/) (bootstrap, maintenance, DR)

## Context7

- **Catalog**: [docs/context7-libraries.json](docs/context7-libraries.json) - pre-approved library IDs
- **Behavior**: Auto-fetch for catalog libraries; ask before resolving new ones
- **Versioning**: Match cluster versions when available
