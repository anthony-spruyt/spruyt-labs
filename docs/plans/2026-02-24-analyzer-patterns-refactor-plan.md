# Analyzer Patterns Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close the self-improvement feedback loop so the renovate-pr-analyzer reads accumulated patterns from the reference file, and eliminate duplicate domain knowledge between the agent and reference file.

**Architecture:** Slim the agent to a generic process engine, centralize all domain-specific patterns in `analysis-patterns.md`, and have the processor skill inject the file path in the dispatch prompt.

**Tech Stack:** Claude Code agents, skills, markdown

**Design doc:** `docs/plans/2026-02-24-analyzer-patterns-refactor-design.md`

**Closes:** #537

---

### Task 1: Add dependency type classification and changelog strategies to analysis-patterns.md

The classification table (agent lines 33-38) and per-type changelog strategies (agent lines 50-79) currently exist only in the agent. Move them to the reference file so the agent can load them from there.

**Files:**

- Modify: `.claude/skills/renovate-pr-processor/references/analysis-patterns.md:1-4`

**Step 1: Add the classification table**

Insert a new section after line 3 (after the intro paragraph), before `## Helm Chart Updates`:

```markdown
## Dependency Type Classification

Classify each Renovate PR by matching its labels and changed files:

| Label / File Pattern | Type | Upstream Source |
|----------------------|------|----------------|
| `renovate/helm` + `release.yaml` changed | Helm chart | Chart's GitHub repo |
| `renovate/image` + image tag changed | Container image | Image project's GitHub repo |
| `renovate/taskfile` + `.taskfiles/` changed | Taskfile dep | Project's GitHub repo |
| None of the above | Other | Best-effort GitHub search |
```

**Step 2: Add per-type changelog fetch strategies**

Insert a new section before `## Changelog Parsing Heuristics` (line 106):

````markdown
## Upstream Changelog Fetch Strategies

Follow research priority: Context7 → GitHub → WebFetch → WebSearch (last resort).

**For Helm charts:**

Find the chart's source repo from the PR body or HelmRepository source (see "Upstream Repo Discovery for Helm Charts" above).

```bash
gh release list --repo <upstream-repo> --limit 10
gh release view <tag> --repo <upstream-repo>
```

**For container images:**

Find the image project repo from the image name. Check the PR body for source links, or search GitHub.

```bash
gh release list --repo <upstream-repo> --limit 10
gh release view <tag> --repo <upstream-repo>
```

**For Taskfile dependencies:**

The project repo is usually in the Taskfile dependency URL or version comment.

```bash
gh release list --repo <upstream-repo> --limit 10
gh release view <tag> --repo <upstream-repo>
```

**Fallback — CHANGELOG.md:**

```
WebFetch: https://raw.githubusercontent.com/<org>/<repo>/main/CHANGELOG.md
```

**Context7 for well-known projects:**

```
resolve-library-id(libraryName: "<project>", query: "changelog breaking changes <version>")
query-docs(libraryId: "<resolved-id>", query: "breaking changes migration <version>")
```
````

**Step 3: Add cross-reference procedures for impact assessment**

The agent's Step 6b (lines 123-150) contains per-type cross-reference procedures that belong in the knowledge base. Insert these into the existing `## Impact Assessment Against Our Config` section, after the "Where Our Config Lives" subsection (after line 195), replacing the existing `### Impact Assessment Patterns` section. The content already exists in the patterns file at lines 197-240 — verify it covers these procedures from the agent:

- Helm chart value changes (renamed/removed keys)
- CRD changes
- Default value changes
- Container image config/env changes
- API version bumps

If any are missing, add them. The patterns file already has most of these — just verify completeness.

**Step 4: Verify the file reads cleanly**

Read the full file back and confirm:
- New sections are in logical order
- No duplicate content between old and new sections
- Markdown formatting is correct

**Step 5: Commit**

```bash
git add .claude/skills/renovate-pr-processor/references/analysis-patterns.md
git commit -m "fix(skills): add dep classification and changelog strategies to analysis patterns

Moves dependency type classification table and per-type changelog
fetch strategies from the analyzer agent into the shared reference
file, preparing for agent slimdown.

Ref #537

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Slim renovate-pr-analyzer.md to generic process engine

Remove all baked-in domain patterns and add Step 0 to read the reference file. The agent should contain ONLY workflow logic, not domain knowledge.

**Files:**

- Modify: `.claude/agents/renovate-pr-analyzer.md`

**Step 1: Add Step 0 after `## Process` (line 19), before `### Step 1`**

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

**Step 2: Replace Step 2 (lines 31-38)**

Replace the entire Step 2 section (classification table) with:

```markdown
### Step 2: Classify Dependency Type

Using the dependency type classification table from the analysis patterns (Step 0), match the PR's labels and changed files to determine the dependency type and upstream source.
```

**Step 3: Replace Step 4 (lines 50-79)**

Replace the entire Step 4 section (per-type changelog strategies) with:

```markdown
### Step 4: Fetch Upstream Changelog

Follow the changelog fetch strategies from the analysis patterns (Step 0). Use the research priority: Context7 → GitHub → WebFetch → WebSearch (last resort).

Use the known upstream repo mappings from the patterns to resolve chart/image names to GitHub repos.
```

**Step 4: Replace Step 6 (lines 92-158)**

Replace the entire Step 6 section (per-type impact analysis) with:

```markdown
### Step 6: Impact Analysis Against Our Configuration

**This is the most critical step.** A breaking change only matters if it affects what we actually use. You MUST cross-reference every breaking change against our real config.

Using the impact assessment procedures from the analysis patterns (Step 0):

1. **Locate config files** — use the config file location map from the patterns to find the relevant files for the affected app. Read them using the Glob and Read tools.
2. **Cross-reference each breaking change** — for each breaking change or deprecation found in Steps 4-5, follow the per-type procedures from the patterns to determine whether it affects our configuration.
3. **Classify impact** using the standard levels:

| Impact Level | Meaning |
|-------------|---------|
| **NO_IMPACT** | Breaking change exists but we don't use the affected feature/config |
| **LOW_IMPACT** | Default changed but we may not notice; or deprecation warning only |
| **HIGH_IMPACT** | We use the affected config/feature — will break on upgrade |
| **UNKNOWN_IMPACT** | Cannot determine if we use the affected feature |

Consult the common NO_IMPACT and HIGH_IMPACT scenario tables from the patterns to inform your classification.
```

**Step 5: Replace Step 7 (lines 160-235)**

Replace everything from `### Step 7: Evaluate and Format Findings` through the end of the output format block (line 235) with:

```markdown
### Step 7: Evaluate and Determine Verdict

Use the scoring heuristic and red flag keywords from the analysis patterns (Step 0) to evaluate the overall risk.

**SAFE criteria (ALL must be true):**

- No breaking changes found, OR all breaking changes have **NO_IMPACT** on our config
- No open bugs with high engagement (>5 reactions) for target version
- Breaking changes exist but verified that we don't use the affected features

**RISKY criteria (ANY is true):**

- Breaking change with **HIGH_IMPACT** — we use the affected config/feature
- Known bugs with significant engagement affecting features we use
- Migration steps required that affect our deployment

**SAFE despite breaking changes (important distinction):**

- Major version bump BUT all breaking changes are **NO_IMPACT** → still SAFE
- CRD changes BUT we don't use that CRD kind → still SAFE
- Value renamed BUT we don't set that value → still SAFE

**UNKNOWN criteria:**

- Cannot find upstream repo or changelog
- Changelog is empty or unhelpful
- Cannot determine scope of changes
- Breaking change found but **UNKNOWN_IMPACT** — cannot verify if we use the feature

**Format your findings using EXACTLY this structure** — the orchestrating skill parses it:

```
## VERDICT: [SAFE|RISKY|UNKNOWN]

**PR:** #<number> - <title>
**Dep Type:** [helm|image|taskfile|other]
**Version Change:** <old> → <new> (<patch|minor|major>)

### Reasoning
<2-3 sentences explaining the verdict, focusing on IMPACT not just existence of breaking changes>

### Breaking Changes & Impact Assessment
| Breaking Change | Our Config Uses It? | Impact | Evidence |
|----------------|--------------------:|--------|----------|
| <change description> | Yes/No | NO_IMPACT / LOW_IMPACT / HIGH_IMPACT / UNKNOWN_IMPACT | <file:key or "not found in values.yaml"> |

<If no breaking changes: "None found">

### Config Files Checked
<List the actual files you read to assess impact, e.g.:>
- `cluster/apps/<ns>/<app>/app/values.yaml` — <N> keys checked
- `cluster/apps/<ns>/<app>/app/release.yaml` — inline values checked
- `cluster/apps/<ns>/<app>/ks.yaml` — substitutions checked

### Upstream Issues
<List of relevant open issues, or "None found">

### Changelog Summary
<Key changes in the new version, 3-5 bullet points>

### Source
<URLs consulted for this analysis>

### Suggested Improvements
<List any improvements to the analysis-patterns reference based on this run, or "None">
Examples of useful feedback:
- "Missing upstream repo mapping: <helm-repo-url> → <github-org/repo>"
- "Changelog format not covered: <describe format seen>"
- "New breaking change signal worth adding: <pattern>"
- "False positive: <pattern> flagged but never relevant for this repo"
- "Config path not checked: <path> should be included in impact analysis"
```
```

Note: The `### Suggested Improvements` section wording changes from "agent or analysis-patterns reference" to just "analysis-patterns reference" since the agent is now generic.

**Step 6: Verify the agent file reads cleanly**

Read the full file back and confirm:
- Step numbering is consistent (0-9)
- All references to "analysis patterns (Step 0)" make sense
- Steps 1, 3, 5, 8, 9 and Critical Rules are unchanged
- Output format block is intact
- No leftover domain-specific content in Steps 2, 4, 6, 7

**Step 7: Commit**

```bash
git add .claude/agents/renovate-pr-analyzer.md
git commit -m "fix(skills): slim analyzer agent to generic process engine

Removes baked-in domain patterns from Steps 2, 4, 6, 7 and adds
Step 0 to load patterns from the reference file. The agent now
references the analysis-patterns.md knowledge base for all
domain-specific detection logic.

Ref #537

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Update processor dispatch prompt in SKILL.md

Add the analysis patterns file path to the dispatch prompt so the analyzer knows where to find it.

**Files:**

- Modify: `.claude/skills/renovate-pr-processor/SKILL.md:69-77`

**Step 1: Update the Phase 2 dispatch prompt**

Replace lines 69-77 (the dispatch prompt block) with:

```
For each PR, use Task tool with:
  subagent_type: "renovate-pr-analyzer"
  run_in_background: true
  prompt: "Analyze Renovate PR #<number> in anthony-spruyt/spruyt-labs for breaking changes.
           GitHub issue: #<tracking-issue-number>
           Repository: anthony-spruyt/spruyt-labs
           Analysis patterns: .claude/skills/renovate-pr-processor/references/analysis-patterns.md
           Return your analysis in the MANDATORY output format specified in your instructions."
```

**Step 2: Verify the skill file reads cleanly**

Read the file back and confirm the dispatch prompt includes the `Analysis patterns:` line.

**Step 3: Commit**

```bash
git add .claude/skills/renovate-pr-processor/SKILL.md
git commit -m "fix(skills): inject analysis patterns path into analyzer dispatch prompt

The processor now tells the analyzer where to find the reference
file, completing the feedback loop: Phase 5b writes patterns →
next run's analyzers read them.

Ref #537

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Final verification

Confirm all three files are consistent and the feedback loop is complete.

**Files:**

- Read: `.claude/skills/renovate-pr-processor/references/analysis-patterns.md`
- Read: `.claude/agents/renovate-pr-analyzer.md`
- Read: `.claude/skills/renovate-pr-processor/SKILL.md`

**Step 1: Verify data flow**

1. SKILL.md dispatch prompt includes `Analysis patterns: .claude/skills/renovate-pr-processor/references/analysis-patterns.md`
2. Agent Step 0 reads the file from the path in the dispatch prompt
3. Agent Steps 2/4/6/7 reference "analysis patterns (Step 0)"
4. Agent output format includes `### Suggested Improvements` targeting the patterns file
5. SKILL.md Phase 5b writes improvements to `references/analysis-patterns.md`

**Step 2: Verify no duplicate knowledge**

Confirm the agent contains NO:
- Dependency type classification tables
- Per-type bash command examples for fetching changelogs
- Per-type cross-reference procedures
- Red flag keyword lists
- Scoring heuristics
- Common NO_IMPACT/HIGH_IMPACT scenario tables
- Helm chart/image/taskfile specific patterns

All of these should be ONLY in `analysis-patterns.md`.

**Step 3: Verify patterns file completeness**

Confirm `analysis-patterns.md` contains ALL of:
- Dependency type classification table (new)
- Per-type changelog fetch strategies (new)
- Per-type breaking change signal tables (existing)
- Upstream repo mappings (existing)
- Impact assessment procedures (existing, verify completeness)
- Config file location map (existing)
- Red flag keywords and scoring heuristic (existing)
- Common NO_IMPACT/HIGH_IMPACT scenarios (existing)
- GitHub release notes format patterns (existing)
