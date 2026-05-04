# Agent Queue Worker — Job Schema v2

## Summary

Restructure the job input schema from a discriminated union with role-specific fields at root level to an **envelope + typed data** pattern. Flatten compound roles (sre) into distinct role names. Rename roles for clarity and future extensibility.

## Motivation

- Role-specific fields (`pr_number`, `head_sha`, `issue_number`, `dedup_key`) live at root level alongside common fields, causing confusion for callers (n8n)
- Field naming inconsistencies between caller and schema (`dedupe_key` vs `dedup_key`) cause silent validation failures
- The `sre` role uses conditional logic (trigger-based branching) that should be separate roles
- Current role names (`triage`, `fix`, `execute`) are too generic for a system that will add `pr-fix` and other job types

## Design

### Wire Format

Every job submission follows the same envelope shape:

```ts
interface AgentJobInput {
  role: Role;           // discriminator — determines data shape
  repo: string;        // scope — always required
  priority: number;    // scheduling — integer >= 1
  event_type: string;  // audit/observability
  data: RoleData;      // typed per role, validated at API boundary
}
```

### Roles and Data Shapes

| Role               | `data` schema                                   | Identity derivation                     |
| ------------------ | ----------------------------------------------- | --------------------------------------- |
| `renovate-triage`  | `{ pr_number: number, head_sha: string }`       | `{repo}--renovate-triage--{pr_number}`  |
| `renovate-fix`     | `{ pr_number: number, head_sha: string }`       | `{repo}--renovate-fix--{pr_number}`     |
| `revert`           | `Record<string, unknown>` (TBD)                 | `{repo}--revert`                        |
| `execute-issue`    | `{ issue_number: number }`                      | `{repo}--execute-issue--{issue_number}` |
| `sre-alert`        | `{ fingerprint: string, [k: string]: unknown }` | `{repo}--sre-alert`                     |
| `sre-health-check` | `{ dedup_key: string }`                         | `{repo}--sre-health-check--{dedup_key}` |
| `validate`         | `Record<string, unknown>` (TBD)                 | `{repo}--validate`                      |

### Validation Strategy

- **Strict per role**: roles with defined schemas reject unknown keys. Catch bad input at the API boundary.
- **Passthrough exceptions**: `sre-alert` requires `fingerprint` but allows extra keys (AlertManager webhook data is variable). `revert` and `validate` are TBD — use `Record<string, unknown>` until schemas are finalized.
- **No cross-field superRefine**: each role's data schema is self-contained. The discriminated union on `role` selects the correct data schema. No conditional validation logic.

### Identity Derivation

Each role definition implements:

```ts
buildIdentity(role: string, repo: string, data: RoleData): string
```

Identity is computed from envelope + data fields. No separate `idempotency_key` on the envelope — BullMQ `jobId` is set to the computed identity string. Deduplication handled by BullMQ's existing duplicate detection + the `onDuplicate` strategy per role.

### Role Definitions (behavior unchanged)

| Role               | Timeout | On Duplicate                     | Buffer             | Staleness Check |
| ------------------ | ------- | -------------------------------- | ------------------ | --------------- |
| `renovate-triage`  | 10min   | replace if waiting, else discard | no                 | yes (head_sha)  |
| `renovate-fix`     | 30min   | replace if waiting, else discard | no                 | yes (head_sha)  |
| `revert`           | 15min   | replace if waiting, else discard | no                 | no              |
| `execute-issue`    | 60min   | discard                          | no                 | no              |
| `sre-alert`        | 15min   | buffer                           | yes (batch alerts) | no              |
| `sre-health-check` | 15min   | replace if waiting, else discard | no                 | no              |
| `validate`         | 30min   | replace if waiting, else discard | no                 | no              |

### n8n Caller Example

```json
{
  "role": "sre-health-check",
  "repo": "anthony-spruyt/spruyt-labs",
  "priority": 10,
  "event_type": "scheduled_health_check",
  "data": {
    "dedup_key": "1777933578163"
  }
}
```

```json
{
  "role": "renovate-triage",
  "repo": "anthony-spruyt/spruyt-labs",
  "priority": 5,
  "event_type": "renovate_pr_opened",
  "data": {
    "pr_number": 499,
    "head_sha": "abc123"
  }
}
```

### Migration

This is a breaking change. All callers (n8n workflows) must update simultaneously with the worker deployment.

1. Update Zod schemas — new `AgentJobInputSchema` with envelope + typed data
1. Update role definitions — `buildIdentitySegments(job)` becomes `buildIdentity(repo, data)`
1. Rename role registry entries
1. Update processor — destructure from `job.data.data` instead of `job.data`
1. Update n8n workflows — restructure HTTP request bodies
1. Drain existing jobs before deploy (or accept they'll fail)

**Breaking behavior changes beyond field restructuring:**

- **`renovate-fix` always requires `pr_number` + `head_sha`** — the old `fix` role accepted optional PR fields when `payload.revert=true`. Reverts now use the dedicated `revert` role instead. Callers must send `role: "revert"` for revert jobs, not `role: "renovate-fix"` without PR fields.
- **`GET /jobs/:id` response shape changes** — role-specific fields (e.g. `pr_number`, `head_sha`) now nest under `data` instead of appearing at the response root. Callers parsing this response must update accordingly.

### Files Affected

- `src/job/schema.ts` — complete rewrite
- `src/job/identity.ts` — simplify, remove registry dependency for extraction
- `src/roles/registry.ts` — new role names
- `src/roles/pr-role.ts` — rename to `renovate-role.ts`, read from `data`
- `src/roles/execute-role.ts` — rename to `execute-issue-role.ts`, read from `data`
- `src/roles/sre-role.ts` — split into `sre-alert-role.ts` and `sre-health-check-role.ts`
- `src/processor.ts` — update field access
- `src/http/routes.ts` — update schema reference, fingerprint check reads `data.fingerprint`
- `src/http/routes.test.ts` — update all test payloads
- n8n workflows (external)

### Constraints

- **Preserve all delay/buffer/batch logic** — `getJobDelay`, `drainBuffer`, `cooldownMs`, `SRE_BATCH_WINDOW_MS` behavior must remain identical. Only the field access paths change (e.g. `job.dedup_key` → `job.data.dedup_key`).
- **Validation errors must include field paths and messages** — When Zod rejects input, the 400 response must include failing field names AND error messages. Example response:
  ```json
  {
    "added": false,
    "reason": "invalid_request",
    "errors": [
      { "field": "data.pr_number", "message": "Required" },
      { "field": "data.head_sha", "message": "String must contain at least 1 character(s)" }
    ]
  }
  ```
  With strict per-role schemas, all validation happens at parse time — role builders no longer throw for missing fields.

### Out of Scope

- `revert` and `validate` data schema finalization (built later)
- `idempotency_key` on envelope (not needed now)
- New roles (`pr-fix`, etc.) — added when needed following this pattern
