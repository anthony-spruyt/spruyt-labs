# project_context.md

Spruyt-labs homelab workspace rules and operating context for contributors.

## Environment overview

- Talos Linux Kubernetes cluster deployed on bare metal hardware.
- No SSH access to Talos nodes; all administration is performed through Talos APIs, `talosctl`, Flux, or Kubernetes resources.
- Supporting cloud infrastructure is managed through Terraform manifests in the `infra/` directory.
- Talos machine configuration lives in the `talos/` directory.
- The repository is designed for the VS Code devcontainer, which ships with `kubectl`, `talosctl`, `talhelper`, `gh`, `terraform`, and Taskfile support.

## Day-to-day guidelines

- Always test changes with linting or validation after any task to confirm successful completion. Never assume success; verify explicitly before proceeding with any further actions.
- Query the live cluster with `kubectl` or `talosctl` to validate assumptions before making changes.
- Keep GitHub Actions definitions in `.github/` aligned with repository workflows.
- Review [`kubernetes.md`](kubernetes.md) for kubectl verification steps before touching Kubernetes manifests.
- Prefer automation (Flux, Terraform, Talos declarative configs) over manual intervention to avoid configuration drift.
- **Always use Taskfile tasks first** for any development operations (e.g., `task dev-env:lint` for linting) instead of running underlying scripts directly. Only run scripts manually if the Taskfile task is unavailable or insufficient.
- **Always test changes with linting or validation before committing** (e.g., `task dev-env:lint` for documentation and code checks).
- Evaluate available MCP servers before resorting to ad-hoc web searches.
- **Automation Decisions**: Use Taskfile tasks for any multi-step or repetitive process; reserve manual commands for one-off verifications or when Taskfile equivalents are unavailable.

## Related documents

- [`kubernetes.md`](kubernetes.md) — detailed kubectl workflow and command reference.
- [`shared-procedures.md`](shared-procedures.md) — common operational patterns and MCP workflows.
- [`user_context7_libraries.md`](user_context7_libraries.md) — Context7 library usage policy.
- `../context7-libraries.json` — catalog of approved Context7 libraries.
- `../mcp.json` — MCP server definitions and tool allowances.

Keep related guidance synchronized to avoid conflicting instructions across documents.

## Changelog

- 2025-11-29 · Added Automation Decisions bullet in Day-to-day guidelines section.
