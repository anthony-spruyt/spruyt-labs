# Dispatcher Prompt Extraction Design

Extract embedded prompts from the Agent Platform Dispatcher n8n workflow into version-controlled markdown files, mounted via ConfigMap, with a reusable sub-workflow for loading and interpolating prompt templates.

## Motivation

The Dispatcher workflow (OSijNQIHmleG7qXZ) builds prompts for triage, validate, and fix roles inside JavaScript Code nodes using string concatenation. This makes prompts:

- Hard to read and edit (escaped newlines, quotes in JS)
- Impossible to version-track meaningfully (buried in n8n workflow JSON)
- Not reviewable in PRs (changes show as Code node parameter diffs)

## Design

### File Structure

New prompt files under the `app/` directory (kustomize requires files to be in or below the kustomization root):

```text
cluster/apps/n8n-system/n8n/app/prompts/
├── dispatcher-triage-prompt.md   # new
├── dispatcher-validate-prompt.md # new
└── dispatcher-fix-prompt.md      # new
```

Existing files in `assets/` (`health-check-prompt.md`, `sre-triage-prompt.md`) remain unchanged and are excluded from this ConfigMap. They will migrate to the agent platform later.

Each file is a self-contained markdown prompt template with `<<KEY>>` markers for runtime variable interpolation. Marker syntax chosen for zero conflict with n8n expressions (`{{}}`), markdown, and JavaScript template literals.

### ConfigMap & Volume Mount

Add a `configMapGenerator` entry in `cluster/apps/n8n-system/n8n/app/kustomization.yaml`:

```yaml
configMapGenerator:
  - name: n8n-prompts
    namespace: n8n-system
    options:
      disableNameSuffixHash: true
    files:
      - prompts/dispatcher-triage-prompt.md
      - prompts/dispatcher-validate-prompt.md
      - prompts/dispatcher-fix-prompt.md
```

`disableNameSuffixHash: true` prevents kustomize from appending a hash suffix to the ConfigMap name. Without this, the volume mount in `values.yaml` (which references `n8n-prompts` by static name) would not match the generated name. The `reloader.stakater.com/auto: "true"` annotation already handles pod restarts on ConfigMap content changes, so the hash suffix rollout mechanism is not needed.

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

Files appear at `/home/node/.n8n-files/prompts/<filename>.md`.

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

1. **When Called By Another Workflow** — `executeWorkflowTrigger` (passthrough mode), receives `filePath` and `variables`
1. **Read Prompt File** — `readWriteFile` (read mode), path from input `filePath`
1. **Interpolate Variables** — `code` node that extracts file content from binary data, performs single-pass regex replacement of `<<KEY>>` markers, and passes through all caller input data alongside the interpolated prompt

Test path (parallel entry point for manual validation):

4. **When clicking 'Execute workflow'** — `manualTrigger`
1. **Test Data** — `code` node with hardcoded sample `filePath` and `variables` matching one of the dispatcher templates, feeds into **Read Prompt File**

Both paths converge at **Read Prompt File**. The test path allows clicking "Execute workflow" in the n8n editor to validate interpolation without needing a caller workflow.

**Output:** `{ ...callerInputData, "prompt": "...fully interpolated text..." }`

The sub-workflow passes through all caller input fields (`repo`, `payload`, `fix_model`, etc.) alongside the interpolated `prompt`. This is critical because downstream Claude Code nodes reference fields like `$json.repo` and `$json.fix_model` from the same item.

**Interpolation logic:**

The `readWriteFile` node returns file content as binary data (not JSON). The Code node must use `this.helpers.getBinaryDataBuffer()` to extract the text, matching the proven pattern in the existing "Get Skynet RW Token" workflow.

```javascript
const binaryData = $input.first().binary;
if (!binaryData) {
  throw new Error('No binary data — prompt file may not exist at the specified path');
}
const key = Object.keys(binaryData)[0];
const buffer = await this.helpers.getBinaryDataBuffer(0, key);
const fileContent = buffer.toString('utf8');

let inputData;
try {
  inputData = $('When Called By Another Workflow').first().json;
} catch {
  inputData = $('Test Data').first().json;
}
const variables = inputData.variables || {};

const prompt = fileContent.replace(/<<([A-Z0-9_]+)>>/g, (match, varKey) => {
  return varKey in variables ? String(variables[varKey]) : match;
});

return [{ json: { ...inputData, prompt } }];
```

**Safety properties:**

- **Single-pass** — injected values are never re-scanned, so a `TRIAGE_SUMMARY` containing `<<HEAD_SHA>>` won't be double-interpolated
- **Unmatched markers pass through** — makes missing variables obvious in output rather than silently empty
- **Key restriction** — `[A-Z0-9_]+` regex prevents injection via malformed key names
- **Data passthrough** — all caller input fields are preserved in the output, so downstream nodes retain access to `repo`, `payload`, `fix_model`, etc.
- **Dual-path variable resolution** — try/catch falls back from trigger node to Test Data node, so both production and test paths work

### Dispatcher Workflow Changes

Each of the 3 "Build X Prompt" Code nodes is replaced with 2 nodes:

1. **Prepare X Variables** — Code node extracting dynamic values from `$('Restore Dispatch Data')` into `{filePath, variables}` format
1. **Load X Prompt** — `executeWorkflow` node (typeVersion 1.1, `source: "database"`) calling the sub-workflow by ID. TypeVersion 1.1 supports passthrough mode, which forwards all item JSON fields to the sub-workflow without requiring explicit `workflowInputs` mapping.

Node count per role: 1 → 2. Total workflow change: 3 nodes → 6 nodes.

**Triage role** — Prepare node builds variables including computed `CI_SUMMARY` from check run data.

**Validate role** — Prepare node passes job context variables only (simplest).

**Fix role** — Prepare node also computes `fix_model` from complexity. This stays as a direct output of the Prepare node (not part of the prompt template) since it controls Claude model selection. The sub-workflow passes it through in the output.

### Variables Per Template

| File                            | Variables                                                                                                              |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `dispatcher-triage-prompt.md`   | `JOB_ID`, `SESSION_TOKEN`, `REPO`, `PR_NUMBER`, `HEAD_SHA`, `ATTEMPT`, `DISPATCHED_AT`, `CI_OVERALL`, `CI_SUMMARY`     |
| `dispatcher-validate-prompt.md` | `JOB_ID`, `SESSION_TOKEN`, `REPO`, `HEAD_SHA`, `ATTEMPT`, `DISPATCHED_AT`                                              |
| `dispatcher-fix-prompt.md`      | `JOB_ID`, `SESSION_TOKEN`, `REPO`, `PR_NUMBER`, `HEAD_SHA`, `ATTEMPT`, `DISPATCHED_AT`, `COMPLEXITY`, `TRIAGE_SUMMARY` |

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

The Prepare node passes through all original data fields (`...data`) alongside the sub-workflow input, so downstream nodes still have access to `jobId`, `session_token`, etc. The sub-workflow also passes through all input fields in its output, ensuring Claude Code nodes can reference `$json.repo`, `$json.payload`, `$json.fix_model`, etc.

After the Load Prompt sub-workflow returns, the prompt field name fed to the Claude Code node changes from `triage_prompt`/`validate_prompt`/`fix_prompt` to the generic `prompt` returned by the sub-workflow. The Claude Code node expression referencing the prompt field needs updating accordingly.

## Out of Scope

- Migrating health-check and SRE triage workflows to the agent platform (future work)
- Adding `<<KEY>>` markers to existing `health-check-prompt.md` or `sre-triage-prompt.md`
- Shared/composable prompt fragments across roles (accepted duplication for simplicity)
