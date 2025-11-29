# shared-procedures.md

Common operational patterns and procedures for spruyt-labs contributors.

## Basic kubectl Commands

### List available resource types and API groups

```sh
kubectl api-resources
```

### Explain resource specification fields

```sh
kubectl explain <resource_type>[.<field_path>]
```

Use `--recursive` when you need to inspect nested fields.

### Retrieve the live manifest for inspection

```sh
kubectl get <resource_type> <resource_name> -n <namespace> -o yaml
```

## Flux Operations

### Reconcile Kustomization

```sh
flux reconcile kustomization <name> --with-source
```

### Get Kustomization status

```sh
flux get kustomizations -n flux-system
```

### Get HelmRelease status

```sh
flux get helmreleases -n <namespace>
```

### Diff changes before apply

```sh
flux diff ks <name> --path=./path
flux diff hr <name> --namespace <namespace>
```

## MCP Integration Workflow

- Primary MCP endpoint: see [`../mcp.json`](../mcp.json) for the `context7` server configuration.
- Before issuing `resolve-library-id`, consult the pre-approved catalog in [`context7-libraries.json`](../context7-libraries.json).
- When documentation is required, prefer MCP tools (`resolve-library-id`, `get-library-docs`) to ensure citations are consistent and cached.
- Record the library ID, version (if provided), and relevant snippets in your change notes or pull request description.
- If documentation is unavailable or outdated, escalate per the ownership guidance in the root README.md before proceeding.

### Decision Trees for Tool Selection

- **Use MCP tools first**: When documentation is required, always prefer `resolve-library-id` and `get-library-docs` over manual web searches to ensure consistent citations and cached results.
- **Escalate to human operators**: When MCP tools return no matches after precise queries, or when documentation gaps prevent autonomous resolution, involve human operators per escalation criteria in [`error_handling.md`](error_handling.md).
- **Manual searches as fallback**: Reserve ad-hoc web searches only when MCP servers are unavailable or when specific vendor documentation requires real-time access not covered by approved libraries.

## Context7 Library Usage

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../context7-libraries.json) to identify an existing entry that covers your topic.
- Confirm the catalog entry contains the documentation or API details you need before invoking any tools.
- Note the library identifier, source description, and any version information that appears in the catalog.

### When the catalog already covers your need

1. Use the information from [`context7-libraries.json`](../context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant citation details in your working notes, pull request description, or runbook draft.
3. Mention how the retrieved material informed your change (e.g., field defaults, API semantics, upgrade procedure).

### When the required library is missing or outdated

1. Run `resolve-library-id` with a precise description of the documentation you need.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update your worklog with the new ID and any prerequisites uncovered during the search.

## Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in your change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions you made when interpreting the documentation, especially when deviating from defaults.

## After your change

- Ensure the relevant rule or runbook references the same library ID so future contributors reuse consistent sources.
- If you discovered inaccuracies or stale references, open an issue or submit a follow-up change to update [`context7-libraries.json`](../context7-libraries.json) and the associated guidance.

## Changelog

- 2025-11-29 · Added Decision Trees for Tool Selection subsection under MCP Integration Workflow.
