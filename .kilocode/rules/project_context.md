# project_context.md

Spruyt-labs homelab workspace rules and operating context for contributors.

## Environment overview

- Talos Linux Kubernetes cluster deployed on bare metal hardware.
- No SSH access to Talos nodes; all administration is performed through Talos APIs, `talosctl`, Flux, or Kubernetes resources.
- Supporting cloud infrastructure is managed through Terraform manifests in the `infra/` directory.
- Talos machine configuration lives in the `talos/` directory.
- The repository is designed for the VS Code devcontainer, which ships with `kubectl`, `talosctl`, `talhelper`, `gh`, `terraform`, and Taskfile support.

## Day-to-day guidelines

- Query the live cluster with `kubectl` or `talosctl` to validate assumptions before making changes.
- Keep GitHub Actions definitions in `.github/` aligned with repository workflows.
- Review [`kubernetes.md`](kubernetes.md:1) for kubectl verification steps before touching Kubernetes manifests.
- Prefer automation (Flux, Terraform, Talos declarative configs) over manual intervention to avoid configuration drift.
- Evaluate available MCP servers before resorting to ad-hoc web searches.

## Terraform change workflow (quick checklist)

1. `terraform fmt` and `terraform validate` within the `infra/` subdirectories you modify.
2. Run `terraform plan`, capture the output, and annotate any expected changes or surprises.
3. Request review with the plan output attached; ensure reviewers understand blast radius, dependencies, and roll-back strategy.
4. After approval, `terraform apply` with the exact plan you reviewed. Document the apply run in change notes or tickets.
5. Confirm state file synchronization (remote backend) and monitor downstream systems for drift.

## Talos lifecycle operations (quick checklist)

1. Use `talosctl health` and `talosctl logs -f kubelet` (as needed) to assess cluster health before upgrades or configuration changes.
2. Diff intended vs. live Talos machine config with `talosctl config diff` before applying updates.
3. Apply changes via `talosctl apply-config --insecure --nodes <target>` or Flux-managed Talos resources, avoiding partial application across control-plane nodes.
4. Verify post-change status with `talosctl health` and Kubernetes node readiness. Capture follow-up actions or anomalies.
5. Coordinate disruptive maintenance windows with platform owners listed in the escalation section.

## MCP integration workflow

- Primary MCP endpoint: see [`../mcp.json`](../mcp.json:1) for the `context7` server configuration.
- Before issuing `resolve-library-id`, consult the pre-approved catalog in [`context7-libraries.json`](../context7-libraries.json:1).
- When documentation is required, prefer MCP tools (`resolve-library-id`, `get-library-docs`) to ensure citations are consistent and cached.
- Record the library ID, version (if provided), and relevant snippets in your change notes or pull request description.
- If documentation is unavailable or outdated, escalate per the ownership guidance below before proceeding.

## Escalation and ownership

- **Cluster operations:** _Owner TBD_ — add contact (Slack channel, email, or on-call rotation). Dependency: platform team to provide canonical contact list.
- **Documentation governance:** _Owner TBD_ — identify who approves rule updates and maintains MCP catalog entries.
- **Terraform infrastructure:** _Owner TBD_ — specify responsible maintainer or triage channel.

> Update the placeholders above once maintainers publish the official contact matrix. Until then, flag ownership gaps in pull requests.

## Related documents

- [`kubernetes.md`](kubernetes.md:1) — detailed kubectl workflow and command reference.
- [`user_context7_libraries.md`](user_context7_libraries.md:1) — Context7 library usage policy.
- `../context7-libraries.json` — catalog of approved Context7 libraries.
- `../mcp.json` — MCP server definitions and tool allowances.

Keep related guidance synchronized to avoid conflicting instructions across documents.
