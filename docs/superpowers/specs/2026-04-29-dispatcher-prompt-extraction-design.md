# Dispatcher Prompt Extraction Design

Extract embedded prompts from the Agent Platform Dispatcher n8n workflow into version-controlled markdown files, mounted via ConfigMap, with a reusable sub-workflow for loading and interpolating prompt templates.

## Motivation

The Dispatcher workflow (OSijNQIHmleG7qXZ) builds prompts for triage, validate, and fix roles inside JavaScript Code nodes using string concatenation. This makes prompts:

- Hard to read and edit (escaped newlines, quotes in JS)
- Impossible to version-track meaningfully (buried in n8n workflow JSON)
- Not reviewable in PRs (changes show as Code node parameter diffs)

## Design

### File Structure

New prompt files in the existing assets directory:

```text
cluster/apps/n8n-system/n8n/assets/
├── health-check-prompt.md        # existing, unchanged
├── sre-triage-prompt.md          # existing, unchanged
├── dispatcher-triage-prompt.md   # new
├── dispatcher-validate-prompt.md # new
└── dispatcher-fix-prompt.md      # new
```

Each file is a self-contained markdown prompt template with `<<KEY>>` markers for runtime variable interpolation. Marker syntax chosen for zero conflict with n8n expressions (`{{}}`), markdown, and JavaScript template literals.

Existing `health-check-prompt.md` and `sre-triage-prompt.md` are manually synced to a separate SRE workflow today and are excluded from this ConfigMap. They will migrate to the agent platform later.

### ConfigMap & Volume Mount

Add a `configMapGenerator` entry in `cluster/apps/n8n-system/n8n/app/kustomization.yaml`:

```yaml
configMapGenerator:
  - name: n8n-prompts
    namespace: n8n-system
    files:
      - ../assets/dispatcher-triage-prompt.md
      - ../assets/dispatcher-validate-prompt.md
      - ../assets/dispatcher-fix-prompt.md
```

Add volume and mount to `values.yaml` shared anchors:

```yaml
extraVolumeMounts: &extraVolumeMounts
  # ... existing mounts ...
  - name: n8n-prompts
    mountPath: /home/node/.n8n-files/prompts
    readOnly: true

extraVolumes: &extraVolumes
  # ... existing volumes ...
  - name: n8n-prompts
    configMap:
      name: n8n-prompts
```

The existing `reloader.stakater.com/auto: "true"` annotation ensures pods restart when the ConfigMap changes. Files appear at `/home/node/.n8n-files/prompts/<filename>.md`.

No `kustomizeconfig.yaml` entry needed — this ConfigMap is a direct volume mount, not a HelmRelease `valuesFrom` reference.

### Sub-Workflow: Load & Interpolate Prompt

A new generic n8n sub-workflow callable by any workflow via `executeWorkflow`.

**Input contract:**

```json
{
  "filePath": "/home/node/.n8n-files/prompts/dispatcher-triage-prompt.md",
  "variables": {
    "JOB_ID": "abc-123",
    "SESSION_TOKEN": "tok-xyz",
    "REPO": "anthony-spruyt/spruyt-labs"
  }
}
```

**Nodes (5 total — 3 production + 2 test):**

Production path:

1. **When Called By Another Workflow** — `executeWorkflowTrigger`, receives `filePath` and `variables`
1. **Read Prompt File** — `readWriteFile` (read mode), path from input `filePath`
1. **Interpolate Variables** — `code` node that performs single-pass regex replacement of `<<KEY>>` markers

Test path (parallel entry point for manual validation):

4. **When clicking 'Execute workflow'** — `manualTrigger`
1. **Test Data** — `code` node with hardcoded sample `filePath` and `variables` matching one of the dispatcher templates, feeds into **Read Prompt File**

Both paths converge at **Read Prompt File**. The test path allows clicking "Execute workflow" in the n8n editor to validate interpolation without needing a caller workflow.

**Output:** `{ "prompt": "...fully interpolated text..." }`

**Interpolation logic:**

```javascript
const fileContent = $('Read Prompt File').first().json.data;
const variables = $('When Called By Another Workflow').first().json.variables;

const prompt = fileContent.replace(/<<([A-Z_]+)>>/g, (match, key) => {
  return key in variables ? String(variables[key]) : match;
});

return [{ json: { prompt } }];
```

**Safety properties:**

- **Single-pass** — injected values are never re-scanned, so a `TRIAGE_SUMMARY` containing `<<HEAD_SHA>>` won't be double-interpolated
- **Unmatched markers pass through** — makes missing variables obvious in output rather than silently empty
- **Key restriction** — `[A-Z_]+` regex prevents injection via malformed key names

### Dispatcher Workflow Changes

Each of the 3 "Build X Prompt" Code nodes is replaced with 2 nodes:

1. **Prepare X Variables** — Code node extracting dynamic values from `$('Restore Dispatch Data')` into `{filePath, variables}` format
1. **Load X Prompt** — `executeWorkflow` node calling the sub-workflow

Node count per role: 1 → 2. Total workflow change: 3 nodes → 6 nodes.

**Triage role** — Prepare node builds variables including computed `CI_SUMMARY` from check run data.

**Validate role** — Prepare node passes job context variables only (simplest).

**Fix role** — Prepare node also computes `fix_model` from complexity. This stays as a direct output of the Prepare node (not part of the prompt template) since it controls Claude model selection.

### Variables Per Template

| File                            | Variables                                                                                                          |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `dispatcher-triage-prompt.md`   | `JOB_ID`, `SESSION_TOKEN`, `REPO`, `PR_NUMBER`, `HEAD_SHA`, `ATTEMPT`, `DISPATCHED_AT`, `CI_OVERALL`, `CI_SUMMARY` |
| `dispatcher-validate-prompt.md` | `JOB_ID`, `SESSION_TOKEN`, `REPO`, `HEAD_SHA`, `ATTEMPT`, `DISPATCHED_AT`                                          |
| `dispatcher-fix-prompt.md`      | `JOB_ID`, `SESSION_TOKEN`, `REPO`, `PR_NUMBER`, `HEAD_SHA`, `COMPLEXITY`, `TRIAGE_SUMMARY`                         |

No dangling `<<KEY>>` markers remain after interpolation — every marker in a file has a corresponding variable in the Prepare node for that role.

### Connection Wiring

For each role, the data flow changes from:

```text
[Previous Node] → Build X Prompt → Claude Code (X)
```

To:

```text
[Previous Node] → Prepare X Variables → Load X Prompt → Claude Code (X)
```

The Prepare node passes through all original data fields (`...data`) alongside the sub-workflow input, so downstream nodes still have access to `jobId`, `session_token`, etc.

After the Load Prompt sub-workflow returns, the prompt field name fed to the Claude Code node changes from `triage_prompt`/`validate_prompt`/`fix_prompt` to the generic `prompt` returned by the sub-workflow. The Claude Code node expression referencing the prompt field needs updating accordingly.

## Out of Scope

- Migrating health-check and SRE triage workflows to the agent platform (future work)
- Adding `<<KEY>>` markers to existing `health-check-prompt.md` or `sre-triage-prompt.md`
- Shared/composable prompt fragments across roles (accepted duplication for simplicity)
