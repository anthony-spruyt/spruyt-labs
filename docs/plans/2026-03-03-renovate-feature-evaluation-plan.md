# Renovate Feature Evaluation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add feature opportunity evaluation to the renovate PR workflow so the analyzer identifies new features relevant to the homelab and the skill consolidates them into a separate GitHub issue.

**Architecture:** The analyzer gets a new step between impact analysis and verdict that evaluates changelog "Added"/"Features" entries against the deployed config. The skill gets a new phase that collects feature opportunities from all analyzer outputs and creates a dedicated GitHub issue. Both changes are purely additive — verdict logic and merge flow are untouched.

**Tech Stack:** Claude Code agents/skills (Markdown), GitHub CLI

**Design doc:** `docs/plans/2026-03-03-renovate-feature-evaluation-design.md`

---

### Task 1: Create GitHub Issue

**Step 1: Create tracking issue**

```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "feat(agents): add feature opportunity evaluation to renovate PR workflow" \
  --label "enhancement" \
  --body "$(cat <<'EOF'
## Summary
Add feature opportunity evaluation to the renovate-pr-analyzer agent and renovate-pr-processor skill.

## Motivation
Currently the renovate workflow only evaluates merge safety (breaking changes, deprecations). New features in dependency updates are classified as "informational" and ignored. This means we miss opportunities to adopt new capabilities that are directly relevant to our homelab (e.g., Cilium adding native BGP control plane when we use Cilium).

## Acceptance Criteria
- [ ] Analyzer evaluates "Added"/"Features" changelog entries for relevance to deployed config
- [ ] Analyzer classifies features as HIGH_RELEVANCE, MEDIUM_RELEVANCE, or LOW_RELEVANCE
- [ ] Analyzer includes `### Feature Opportunities` section in output (HIGH/MEDIUM only)
- [ ] Skill collects feature opportunities from all analyzers and creates a separate GitHub issue
- [ ] New "Feature Relevance False Positives" memory table in known-patterns.md
- [ ] analysis-patterns.md has new "Feature Opportunity Signals" section
- [ ] Existing verdict logic (SAFE/RISKY/UNKNOWN) is completely unchanged

## Affected Area
- Tooling (.taskfiles/, scripts)
EOF
)"
```

**Step 2: Note the issue number for subsequent commits**

---

### Task 2: Add Feature Opportunity Signals to analysis-patterns.md

**Files:**
- Modify: `.claude/skills/renovate-pr-processor/references/analysis-patterns.md`

This is a **skill reference file** — follow writing-skills guidelines (reference material for scanning).

**Step 1: Add new section at end of analysis-patterns.md**

Append after the existing "Known Patterns" section:

```markdown
## Feature Opportunity Signals

### Keywords (case-insensitive)

**High signal (likely notable feature):**
- "now supports", "introducing", "new feature", "added support for"
- "enabled by default", "native support", "built-in"

**Medium signal (possibly notable):**
- "added", "new option", "new flag", "new parameter"
- "experimental", "beta", "preview", "opt-in"

**Low signal (skip):**
- "internal", "refactor", "cleanup", "minor improvement"
- "documentation", "typo", "CI", "test"

### Relevance Assessment Against Our Config

A new feature is only relevant if it applies to what we deploy.

| Feature Type | Check | HIGH_RELEVANCE | MEDIUM_RELEVANCE | LOW_RELEVANCE |
|-------------|-------|----------------|------------------|---------------|
| New config option | Is the parent feature in our values.yaml? | Yes, and we'd benefit from the option | Yes, but unclear benefit | Parent feature not used |
| New capability | Do we deploy this component? | Yes, replaces a workaround or fills a gap | Yes, but no immediate need | Component not deployed |
| Performance improvement | Do we use the affected codepath? | Yes, and we have resource constraints | Possibly | Unrelated codepath |
| New integration | Do we run both systems? | Yes, currently using manual glue | Yes, one or both deployed | Neither deployed |
| Security feature | Does it affect our exposure? | Yes, hardens something we expose | Possibly relevant | Not applicable |

### Architecture-Aware Matching

Cross-reference features against deployed stack by checking:

1. **CRDs in cluster** — `Grep for 'kind:' in cluster/apps/` to find deployed resource types
2. **Helm values** — Features matching keys in `values.yaml` files
3. **Ingress/networking** — Features related to Cilium, Traefik, Cloudflare patterns we use
4. **Storage** — Features related to Rook Ceph patterns we use
5. **Observability** — Features related to VictoriaMetrics, Grafana patterns we use
```

**Step 2: Verify the file is valid markdown and reads cleanly**

```bash
wc -l .claude/skills/renovate-pr-processor/references/analysis-patterns.md
```

Expected: ~185-195 lines (was 141, added ~50).

**Step 3: Commit**

```bash
git add .claude/skills/renovate-pr-processor/references/analysis-patterns.md
git commit -m "feat(agents): add feature opportunity signals to analysis-patterns

Ref #<issue>"
```

---

### Task 3: Add Feature Relevance False Positives Table to known-patterns.md

**Files:**
- Modify: `.claude/agent-memory/renovate-pr-analyzer/known-patterns.md`

**Step 1: Add new table section**

Insert before the existing `## Analysis Notes` section:

```markdown
## Feature Relevance False Positives

Features flagged as relevant that don't apply to this homelab.

| Dependency | Feature | Why NOT Relevant | Count | Last Seen | Added |
|------------|---------|-----------------|------:|-----------|-------|
```

**Step 2: Commit**

```bash
git add .claude/agent-memory/renovate-pr-analyzer/known-patterns.md
git commit -m "feat(agents): add feature relevance false positives table to analyzer memory

Ref #<issue>"
```

---

### Task 4: Update renovate-pr-analyzer Agent

**Files:**
- Modify: `.claude/agents/renovate-pr-analyzer.md`

This is an **agent system prompt** — follow writing-agents guidelines (section order, description field, output format, emphasis calibration, no inherited duplication, size targets).

**Step 1: Read current agent and measure baseline**

```bash
wc -l .claude/agents/renovate-pr-analyzer.md
wc -w .claude/agents/renovate-pr-analyzer.md
```

Note current line/word count for comparison after edits.

**Step 2: Add step 5.5 — Feature Opportunity Analysis**

Insert new section between step 5 (Impact Analysis) and step 6 (Determine Verdict). Add:

```markdown
### 5.5 Feature Opportunity Analysis

Parse "Added"/"Features"/"New" sections from the changelog (already fetched in step 3).

For each notable new feature (matching high/medium signal keywords from analysis-patterns):

1. Research what it does — use Context7, upstream GitHub docs, or README
2. Cross-reference against deployed config (already loaded in step 5): what components are deployed, what config patterns are used, what CRDs exist
3. Evaluate: Does it replace a current workaround? Fill a known gap? Improve an existing pattern?
4. Classify using the relevance assessment table in analysis-patterns
5. Check "Feature Relevance False Positives" in agent memory — suppress matches

Skip this step entirely if the changelog has no "Added"/"Features" sections or only low-signal items.
```

**Step 3: Add Feature Opportunities section to the output format**

In step 7 (Format Output), insert after `### Upstream Issues`:

```markdown
### Feature Opportunities
| Feature | Relevance | Why Relevant | Current State |
|---------|-----------|-------------|---------------|
| <feature name> | HIGH/MEDIUM | <how it applies to our setup> | <what we currently do instead> |

<If none found or all LOW_RELEVANCE: omit this section entirely>
```

**Step 4: Update self-improvement section**

In step 9 (Self-Improvement), add to the "What counts as an observation" list:

```
feature relevance false positive (feature flagged HIGH/MEDIUM that clearly doesn't apply)
```

**Step 5: Verify size is within targets**

```bash
wc -l .claude/agents/renovate-pr-analyzer.md
wc -w .claude/agents/renovate-pr-analyzer.md
```

Target: under 300 lines, under 2,000 words. If over, look for Opus-known content or inherited context to trim elsewhere in the agent.

**Step 6: Commit**

```bash
git add .claude/agents/renovate-pr-analyzer.md
git commit -m "feat(agents): add feature opportunity analysis to renovate-pr-analyzer

Adds step 5.5 for evaluating new features from changelogs against
deployed config. Outputs Feature Opportunities table for HIGH/MEDIUM
relevance items. Updates self-improvement to track false positives.

Ref #<issue>"
```

---

### Task 5: Update renovate-pr-processor Skill

**Files:**
- Modify: `.claude/skills/renovate-pr-processor/SKILL.md`

This is a **skill file** — follow writing-skills guidelines (CSO, token efficiency, flowchart usage, structure).

**Step 1: Read current skill and measure baseline**

```bash
wc -l .claude/skills/renovate-pr-processor/SKILL.md
wc -w .claude/skills/renovate-pr-processor/SKILL.md
```

**Step 2: Add Phase 2.5 — Feature Opportunities Issue**

Insert between Phase 2 (ANALYZE) and Phase 3 (REPORT). Add:

```markdown
### Phase 2.5: FEATURE OPPORTUNITIES

After all analyzers complete, collect `### Feature Opportunities` sections from their outputs.

If any HIGH/MEDIUM relevance features found:

```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "feat(deps): feature opportunities from renovate batch $(date +%Y-%m-%d)" \
  --label "enhancement" \
  --body "$(cat <<'EOF'
## Summary
Notable new features from dependency updates that may be relevant to the homelab.

## Feature Opportunities
| PR | Dependency | Feature | Relevance | Why Relevant | Current State |
|----|-----------|---------|-----------|-------------|---------------|
| #N | <dep> | <feature> | HIGH/MEDIUM | <why> | <current> |

## Motivation
These features were identified during automated Renovate PR analysis. Review at your convenience — none affect merge safety.

## Affected Area
- Apps (cluster/apps/)
EOF
)"
```

If no HIGH/MEDIUM features found across any PR, skip issue creation entirely.
```

**Step 3: Update Phase 3 (REPORT) — mention feature opportunities**

After the existing summary table description, add:

```markdown
If a feature opportunities issue was created in Phase 2.5, mention it: "Feature opportunities tracked in #<number>."
```

**Step 4: Update Phase 5 (SUMMARY) — include feature issue link**

In the final report description, add to the list of items posted to the tracking issue:

```markdown
Feature Opportunities: #<number> (or "None identified")
```

**Step 5: Verify size**

```bash
wc -l .claude/skills/renovate-pr-processor/SKILL.md
wc -w .claude/skills/renovate-pr-processor/SKILL.md
```

Skill should remain scannable and concise.

**Step 6: Commit**

```bash
git add .claude/skills/renovate-pr-processor/SKILL.md
git commit -m "feat(agents): add feature opportunities phase to renovate-pr-processor skill

Adds Phase 2.5 that collects feature opportunities from analyzer outputs
and creates a separate GitHub issue. Updates Phase 3 and Phase 5 to
reference the feature opportunities issue.

Ref #<issue>"
```

---

### Task 6: Validate Agent Changes (writing-agents Phase 2)

Follow the writing-agents validation workflow. Dispatch two parallel sub-agents:

**Sub-agent 1: Structural review**
- Read the modified `renovate-pr-analyzer.md`
- Check: frontmatter fields intact, description under 1024 chars, no workflow summary in description, examples have `<commentary>`, emphasis calibrated (strong only on safety gates), output format present, size under 300 lines / 2,000 words
- Return PASS/FAIL with specific issues

**Sub-agent 2: Effectiveness review**
- Compare modified agent to original via `git show HEAD~1:.claude/agents/renovate-pr-analyzer.md`
- Verify: all original workflow steps intact, no inherited context duplicated, no Opus-known explanations added, domain commands preserved, new feature analysis step complete
- Return EFFECTIVE/DEGRADED

**If FAIL or DEGRADED:** Fix issues and re-validate until PASS + EFFECTIVE.

---

### Task 7: Validate Skill Changes (writing-skills quality checks)

Review the modified skill against writing-skills quality checks:
- Description still matches triggering conditions
- No flowchart needed for the new phase (linear, not a decision point)
- Quick reference table still accurate
- Token efficiency — new content is concise
- No narrative storytelling

---

### Task 8: Run qa-validator

Dispatch qa-validator agent to validate all changes before final commit (if any fixes needed from Tasks 6-7).

---

### Task 9: Close Issue

After user pushes and confirms everything works:

```bash
gh issue close <number> --repo anthony-spruyt/spruyt-labs
```
