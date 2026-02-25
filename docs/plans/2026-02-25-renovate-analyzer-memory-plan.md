# Renovate PR Analyzer Memory Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add project memory to the renovate-pr-analyzer agent so it accumulates knowledge about dependency patterns across runs, and remove the manual self-improvement step from the skill.

**Architecture:** Move dynamic learnings (repo mappings, NO/HIGH_IMPACT scenarios, per-dep quirks) from the static `analysis-patterns.md` reference into agent memory (`known-patterns.md`). Add a self-improvement loop to the agent. Remove Phase 5b from the skill.

**Tech Stack:** Claude Code agents, agent memory (`memory: project` frontmatter)

**Issue:** #542

---

### Task 1: Create agent memory directory and files

**Files:**
- Create: `.claude/agent-memory/renovate-pr-analyzer/MEMORY.md`
- Create: `.claude/agent-memory/renovate-pr-analyzer/known-patterns.md`

**Step 1: Create MEMORY.md**

```markdown
# Renovate PR Analyzer Memory

Accumulated knowledge about dependency update patterns, breaking change analysis, and upstream quirks.

## Index

- [known-patterns.md](./known-patterns.md) — Dependency quirks, false positives, repo mappings, impact scenarios
```

**Step 2: Create known-patterns.md with empty tables**

```markdown
# Known Patterns

## Changelog Quirks

Dependency-specific notes about changelog formats, release patterns, and analysis shortcuts.

| Dependency | Quirk | Count | Last Seen | Added |
|------------|-------|-------|-----------|-------|

## Breaking Change False Positives

Breaking changes flagged by analysis that don't actually affect our config.

| Dependency | Breaking Change | Why NO_IMPACT | Count | Last Seen | Added |
|------------|----------------|---------------|-------|-----------|-------|

## Upstream Repo Mappings

Discovered mappings from Helm repo URLs or image names to GitHub repos.

| Source | GitHub Repo | Count | Last Seen | Added |
|--------|-------------|-------|-----------|-------|

## Common NO_IMPACT Scenarios

Breaking changes that never matter for this homelab.

| Breaking Change | Why Usually NO_IMPACT | Count | Last Seen | Added |
|----------------|----------------------|-------|-----------|-------|

## Common HIGH_IMPACT Scenarios

Breaking changes that frequently affect this homelab.

| Breaking Change | Why Usually HIGH_IMPACT | Count | Last Seen | Added |
|----------------|------------------------|-------|-----------|-------|
```

**Step 3: Commit**

```bash
git add .claude/agent-memory/renovate-pr-analyzer/MEMORY.md .claude/agent-memory/renovate-pr-analyzer/known-patterns.md
git commit -m "feat(agents): add project memory to renovate-pr-analyzer

Create agent memory directory with MEMORY.md index and known-patterns.md
with empty tables for changelog quirks, false positives, repo mappings,
and common impact scenarios.

Ref #542"
```

### Task 2: Strip dynamic content from analysis-patterns.md

**Files:**
- Modify: `.claude/skills/renovate-pr-processor/references/analysis-patterns.md`

Dynamic content to remove and replace with pointers to agent memory:

**Step 1: Replace "Common Helm Chart Patterns" section (lines 33-45)**

Replace:

```markdown
### Common Helm Chart Patterns

**Traefik:** CRD updates are common and usually backward-compatible. Check for middleware API changes.

**Cert-Manager:** CRD updates require careful review. Check for API version bumps (v1alpha1 → v1).

**Grafana/VictoriaMetrics:** Usually safe. Watch for dashboard schema changes.

**Rook-Ceph:** HIGH RISK. Ceph upgrades can affect data availability. Always check Rook compatibility matrix.

**Cilium:** CRD changes are frequent. Check for CiliumNetworkPolicy API changes. BGP config changes can break routing.

**External-Secrets:** Check for ClusterSecretStore API changes.
```

With:

```markdown
### Common Helm Chart Patterns

Check the agent's `known-patterns.md` for dependency-specific quirks accumulated from previous runs. The "Changelog Quirks" table contains per-dependency notes about release patterns and analysis shortcuts.
```

**Step 2: Replace "Upstream Repo Discovery" common mappings list (lines 56-63)**

Replace:

```markdown
3. Common mappings:
   - `https://traefik.github.io/charts` → `traefik/traefik-helm-chart`
   - `https://charts.jetstack.io` → `cert-manager/cert-manager`
   - `https://grafana.github.io/helm-charts` → `grafana/helm-charts`
   - `https://charts.rook.io/release` → `rook/rook`
   - `https://helm.cilium.io/` → `cilium/cilium`
   - `https://charts.external-secrets.io` → `external-secrets/external-secrets`
   - `https://bjw-s.github.io/helm-charts` → `bjw-s/helm-charts` (app-template)
```

With:

```markdown
3. Check the agent's `known-patterns.md` "Upstream Repo Mappings" table for previously discovered mappings
4. If not found, derive the GitHub org from the `spec.url` and search GitHub
```

**Step 3: Replace "Common Image Patterns" section (lines 84-92)**

Replace:

```markdown
### Common Image Patterns

**alpine/git:** Usually safe. Minor bumps add git features. Check for removed commands.

**PostgreSQL:** Minor bumps are safe. Major bumps (15→16) require `pg_upgrade`.

**Redis/Valkey:** Minor bumps are usually safe. Check for deprecated commands.

**Grafana:** Usually safe. Check for plugin API changes.
```

With:

```markdown
### Common Image Patterns

Check the agent's `known-patterns.md` "Changelog Quirks" table for image-specific notes from previous runs.
```

**Step 4: Replace "Common Taskfile Dependencies" section (lines 109-115)**

Replace:

```markdown
### Common Taskfile Dependencies

**helmfile:** Check for command syntax changes. Minor bumps are usually safe.

**talhelper:** Check for talconfig.yaml schema changes.

**flux:** Check for CLI command changes.
```

With:

```markdown
### Common Taskfile Dependencies

Check the agent's `known-patterns.md` "Changelog Quirks" table for taskfile dependency notes from previous runs.
```

**Step 5: Replace "Common NO_IMPACT Scenarios" section (lines 321-332)**

Replace:

```markdown
### Common NO_IMPACT Scenarios

These breaking changes almost never affect this homelab:

| Breaking Change | Why Usually NO_IMPACT |
|----------------|----------------------|
| ARM64 support dropped | We run AMD64 only |
| Windows container changes | Linux-only cluster |
| Cloud provider integration changes | Bare metal, no cloud provider |
| Horizontal Pod Autoscaler changes | Rarely used in homelab |
| PodDisruptionBudget defaults changed | Usually not configured |
| Service mesh integration changes | No service mesh |
```

With:

```markdown
### Common NO_IMPACT Scenarios

Check the agent's `known-patterns.md` "Common NO_IMPACT Scenarios" and "Breaking Change False Positives" tables for patterns accumulated from previous runs.
```

**Step 6: Replace "Common HIGH_IMPACT Scenarios" section (lines 334-345)**

Replace:

```markdown
### Common HIGH_IMPACT Scenarios

These breaking changes frequently affect this homelab:

| Breaking Change | Why Usually HIGH_IMPACT |
|----------------|------------------------|
| CRD API version bump | We use many CRDs (Cilium, Cert-Manager, Traefik) |
| Helm values restructured | We customize most charts heavily |
| Default storage class changed | Rook Ceph is our storage backend |
| Network policy format changed | Cilium policies are critical |
| Ingress annotation changes | Traefik IngressRoutes used everywhere |
```

With:

```markdown
### Common HIGH_IMPACT Scenarios

Check the agent's `known-patterns.md` "Common HIGH_IMPACT Scenarios" table for patterns accumulated from previous runs.
```

**Step 7: Commit**

```bash
git add .claude/skills/renovate-pr-processor/references/analysis-patterns.md
git commit -m "refactor(skills): strip dynamic content from analysis-patterns.md

Move dependency-specific quirks, repo mappings, and impact scenario tables
to agent memory. Replace with pointers to known-patterns.md tables.
Static reference content (classification, signals, heuristics, procedures)
remains unchanged.

Ref #542"
```

### Task 3: Add memory and self-improvement to the agent

**Files:**
- Modify: `.claude/agents/renovate-pr-analyzer.md`

**Step 1: Add `memory: project` to frontmatter**

Add `memory: project` after the `model: sonnet` line (line 4):

```yaml
---
name: renovate-pr-analyzer
description: '...'
model: sonnet
memory: project
---
```

**Step 2: Update Step 0 to also load known patterns**

Replace lines 21-32 (Step 0):

```markdown
### Step 0: Load Analysis Patterns

Your dispatch prompt includes an `Analysis patterns:` field with a file path. Read this file using the Read tool before proceeding. It contains:

- Dependency type classification table
- Per-type breaking change signals and upstream repo mappings
- Changelog fetch strategies
- Impact assessment procedures and config file locations
- Changelog parsing heuristics and scoring logic
- Common NO_IMPACT and HIGH_IMPACT scenarios for this repository

Apply these patterns throughout Steps 1-7 below. If no analysis patterns path is provided, proceed with your best judgment but note this in your output.
```

With:

```markdown
### Step 0: Load Analysis Patterns and Known Patterns

Read TWO files before proceeding:

1. **Static reference** — Your dispatch prompt includes an `Analysis patterns:` field with a file path. Read this file. It contains dependency type classification, breaking change signals, changelog fetch strategies, impact assessment procedures, and scoring heuristics.

2. **Agent memory** — Read `.claude/agent-memory/renovate-pr-analyzer/known-patterns.md`. It contains accumulated learnings from previous runs: changelog quirks, false positives, upstream repo mappings, and common impact scenarios.

Use both throughout Steps 1-7. Known patterns take priority over general heuristics when they apply to the specific dependency being analyzed. If either file is missing, proceed with best judgment but note this in your output.
```

**Step 3: Update Step 6 to reference known patterns**

Replace line 92:

```markdown
Consult the common NO_IMPACT and HIGH_IMPACT scenario tables from the patterns to inform your classification.
```

With:

```markdown
Consult the common NO_IMPACT and HIGH_IMPACT scenario tables from your known patterns memory, plus the "Breaking Change False Positives" table, to inform your classification. If you've seen this exact dependency+breaking change combination before, use the recorded impact.
```

**Step 4: Replace "Suggested Improvements" output section**

Replace lines 157-164:

```markdown
### Suggested Improvements
<List any improvements to the analysis-patterns reference based on this run, or "None">
Examples of useful feedback:
- "Missing upstream repo mapping: <helm-repo-url> → <github-org/repo>"
- "Changelog format not covered: <describe format seen>"
- "New breaking change signal worth adding: <pattern>"
- "False positive: <pattern> flagged but never relevant for this repo"
- "Config path not checked: <path> should be included in impact analysis"
```

With:

```markdown
### Patterns Updated
<"Yes — N new/updated entries" or "No new patterns">
```

**Step 5: Add self-improvement section after Critical Rules (after line 193)**

Append this section at the end of the file:

```markdown
## Self-Improvement (MANDATORY — Run Before Returning Result)

After completing analysis and determining your verdict, record learnings before returning.

### Step 1: Read current patterns

Read `.claude/agent-memory/renovate-pr-analyzer/known-patterns.md` from your agent memory (already loaded in Step 0).

### Step 2: Compare this run against known patterns

For each observation from this run:

- **Already in table** → Increment Count by 1, update Last Seen to today
- **Not in table** → Append new row with Count=1, Last Seen=today, Added=today
- **No new observations** → Skip to returning result

**What counts as an observation:**
- New upstream repo mapping discovered (Source URL → GitHub repo)
- Breaking change that turned out to be NO_IMPACT for our config (add to False Positives)
- Breaking change that turned out to be HIGH_IMPACT for our config (add to HIGH_IMPACT Scenarios)
- Changelog format quirk (empty changelog, unusual format, misleading content)
- Any dependency-specific pattern worth remembering for future runs

### Step 3: Auto-prune (only when file exceeds 50 total entries across all tables)

- Remove entries where Count=1 AND Added is more than 30 days ago
- Never remove entries with Count >= 3
- Log pruned entries in the commit message

### Step 4: Commit if changed

```bash
git add .claude/agent-memory/renovate-pr-analyzer/known-patterns.md
git commit -m "fix(agents): update renovate-pr-analyzer patterns from run YYYY-MM-DD"
```

Only stage this one file. Never stage other files.

### Step 5: Return result

Return your analysis verdict (SAFE/RISKY/UNKNOWN) to the calling agent as normal. The self-improvement step must NOT change the verdict. Update the "Patterns Updated" line in your output to reflect whether you wrote new patterns.
```

**Step 6: Commit**

```bash
git add .claude/agents/renovate-pr-analyzer.md
git commit -m "feat(agents): add self-improvement feedback loop to renovate-pr-analyzer

Add memory: project frontmatter, update Step 0 to load known patterns
alongside static reference, replace Suggested Improvements output with
Patterns Updated, add self-improvement section matching cluster-validator
and qa-validator pattern.

Ref #542"
```

### Task 4: Remove Phase 5b from the skill

**Files:**
- Modify: `.claude/skills/renovate-pr-processor/SKILL.md`

**Step 1: Delete Phase 5b section (lines 233-261)**

Remove the entire block:

```markdown
### Phase 5b: SELF-IMPROVEMENT

Collect all `### Suggested Improvements` sections from the analyzer agents' outputs. If any suggestions were made:

1. Present them to the user grouped by type:
   ```
   ## Suggested Improvements from This Run

   ### Missing Upstream Repo Mappings
   - <helm-repo-url> → <github-org/repo>

   ### New Changelog Patterns Discovered
   - <description>

   ### Analysis Pattern Gaps
   - <description>

   Apply these improvements to the agent/reference files? (Y/N)
   ```

2. If user approves, apply the improvements:
   - **Repo mappings** → add to `references/analysis-patterns.md` under "Upstream Repo Discovery for Helm Charts"
   - **Changelog patterns** → add to `references/analysis-patterns.md` under "GitHub Release Notes Patterns"
   - **New breaking change signals** → add to `references/analysis-patterns.md` under appropriate dep type section
   - **False positives** → add to "Common NO_IMPACT Scenarios" table

3. Commit improvements with message: `fix(skills): update analysis patterns from renovate batch run <date>`

This feedback loop means the analyzer gets smarter with every batch run.
```

**Step 2: Update the Additional Resources section (line 279)**

Replace:

```markdown
- **`references/analysis-patterns.md`** — Detailed breaking change detection patterns by dependency type (Helm, image, taskfile), upstream repo discovery, changelog parsing heuristics, and scoring logic
```

With:

```markdown
- **`references/analysis-patterns.md`** — Static reference: dependency type classification, breaking change signals, changelog fetch strategies, parsing heuristics, and impact assessment procedures
- **Agent memory** — The `renovate-pr-analyzer` agent maintains its own `known-patterns.md` with dynamic learnings (repo mappings, false positives, impact scenarios) that accumulate across runs
```

**Step 3: Commit**

```bash
git add .claude/skills/renovate-pr-processor/SKILL.md
git commit -m "refactor(skills): remove Phase 5b from renovate-pr-processor

The renovate-pr-analyzer agent now handles self-improvement autonomously
via its own agent memory. No manual approval prompt needed.

Ref #542"
```

### Task 5: Update plugin description for renovate-pr-analyzer

**Files:**
- Check: `.claude/plugins/` or `plugin.json` — if the agent description in the plugin manifest mentions "Suggested Improvements" or the old output format, update it to match

**Step 1: Search for agent description references**

```bash
grep -r "renovate-pr-analyzer" .claude/plugins/ --include="*.json" -l
grep -r "Suggested Improvements" .claude/ --include="*.json" -l
```

**Step 2: Update if needed and commit**

Only if references are found that need updating. If the plugin.json auto-derives from the agent frontmatter, this may be a no-op.

```bash
# Only if changes were made:
git add <changed-files>
git commit -m "chore(agents): update renovate-pr-analyzer plugin references

Ref #542"
```
