# CLAUDE.md

Talos Linux homelab GitOps repository on bare metal. No SSH to Talos nodes - use `talosctl`, Flux, or Kubernetes APIs.

## Hard Rules

1. **Declarative only** - No manual kubectl patches for config changes; use Flux, Terraform, Talos configs. Operational commands (restart, scale, drain) via kubectl are permitted.
2. **Trunk-based** - Commit straight to `main` and push without asking. Open a PR only for large, risky work. Mergify exists only to auto-merge bot PRs (Renovate etc.) and is not a merge gate; merge PRs directly with `gh pr merge --squash` (squash is the only merge method the repo allows) and ignore its approval check. This overrides the default guidance to commit only when asked or to branch
   first.
3. **No git amend** - Always new commits
4. **No hardcoded domains** - Use `${EXTERNAL_DOMAIN}` substitution

## Tool Usage

Read and edit files with the `Read` and `Edit` tools rather than `cat`/`head`/`tail` or `sed -i`/`awk -i`; hooks warn on the shell forms. For a quick lookup, search with `grep`, `rg`, or `find` through Bash; for a broad search across many files, use the Explore agent.
