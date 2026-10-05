---
paths: ['**/README.md', 'docs/**/*.md']
---

# Documentation Standards

## Core Rule

Document only what the manifests can't tell you. Anything readable from `ks.yaml`, `release.yaml`, `values.yaml`, or
`kustomization.yaml` (dependencies, names, namespaces, versions, priority class, resources) stays out of docs. Copies
drift; manifests don't.

Exception: `docs/workload-classification.md` is the tier register and lists every workload's tier.

Worth writing down:

- Why a non-default choice was made
- Integration procedures and cross-component wiring
- Credential lifecycle and rotation
- Upstream bugs and workarounds (link the issue and the removal condition)
- Prerequisites outside `ks.yaml` (Talos patches, Terraform, external accounts, manual one-time setup)
- Failure modes whose fix isn't obvious from the error

## Audiences

| Doc                         | Reader              | Purpose                                   |
| --------------------------- | ------------------- | ----------------------------------------- |
| `cluster/apps/**/README.md` | Agents, then humans | Non-obvious knowledge about one component |
| `docs/*.md`                 | Humans, agents down | Runbooks: bootstrap, DR, maintenance      |
| `.claude/**`                | Agents              | Behaviour rules, skills, agent prompts    |

## Component READMEs

- **Optional.** Write one when there is something non-obvious to say. A component that is just a chart with standard
  values needs no README.
- **Create one the moment a change adds non-obvious knowledge**, in the same commit. Triggers: a workaround, a manual
  or one-time step, an external prerequisite, cross-component wiring, a credential to rotate, or a fix you had to
  debug to find. If you had to explain it in the commit body, it probably belongs in a README too.
- Use `docs/templates/readme_template.md`. Overview is required; every other section only when it has real content.
- **Shared READMEs:** when several apps share one design (e.g., `claude-agents-*`), put the doc at the shared level
  (`claude-agents-shared/README.md`) and give each app a one-line pointer README.
- **Namespace READMEs** (`cluster/apps/<ns>/README.md`) are fine for multi-app namespaces with shared architecture
  (e.g., `rook-ceph/`).
- Never document generic `kubectl`/`flux`/`helm` commands. Only component-specific operations.

## Runbooks (`docs/`)

Runbooks must work when agents, MCP servers, and possibly the cluster itself are unavailable.

- **Self-contained:** only tools in the devcontainer (`task`, `talosctl`, `kubectl`, `flux`, `terraform`).
  No agents, MCP tools, or n8n.
- **Copy-pasteable:** numbered steps, exact commands, placeholders as `<node-name>`.
- **Verify each stage:** after each major step, the command that proves it worked and what "good" looks like.
- **State preconditions:** what must be up (e.g., "needs AWS creds", "needs Ceph healthy") before starting.
- **Link to component READMEs** for depth instead of duplicating them.

## Formatting

Markdownlint (via MegaLinter) owns formatting; don't restate its rules here. Beyond the linter:

- Fenced code blocks need a language identifier (`bash`, `yaml`, `json`, `text`)
- Use `${EXTERNAL_DOMAIN}`-style placeholders, never real domains, IPs, or CIDRs

## Maintenance

- A change that makes a doc wrong must update the doc in the same commit
- Delete stale sections rather than leave them; a wrong doc is worse than none
