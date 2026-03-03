# Renovate Feature Evaluation Design

## Summary

Add feature opportunity evaluation to the renovate PR processing workflow. When analyzing dependency updates, the agent evaluates new features for relevance to the homelab and reports them in a separate GitHub issue.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Depth | Deep evaluation | Research each feature, check if it replaces/improves current patterns |
| Output | Separate GitHub issue | Decouples safety analysis from feature exploration |
| Merge impact | Purely informational | Never affects SAFE/RISKY/UNKNOWN verdict |
| Relevance matching | Derive from deployed stack | Uses the config already loaded during impact analysis |
| Adoption tracking | None (implicit) | Agent sees adopted features in config on next run; no feedback mechanism for false relevance |
| Memory | No new tables | Agent has no feedback signal to learn from — relevance matching is config-derived at runtime |

## Changes

### Agent: `renovate-pr-analyzer`

**New step 5.5: Feature Opportunity Analysis** (between impact analysis and verdict determination)

1. Parse "Added"/"Features"/"New" sections from the changelog (already fetched in step 3)
2. For each notable new feature:
   - Research what it does (Context7, GitHub docs, upstream README)
   - Cross-reference against deployed config (already loaded in step 5): what components are deployed, what config patterns are used, what CRDs exist
   - Evaluate: Does it replace a current workaround? Fill a known gap? Improve an existing pattern? Enable something previously impossible?
3. Classify relevance:
   - `HIGH_RELEVANCE` — Directly applicable to current deployment (replaces workaround, improves existing feature we use)
   - `MEDIUM_RELEVANCE` — Potentially useful but requires investigation or config changes
   - `LOW_RELEVANCE` — Not applicable to current setup (skip from output)
4. Add `### Feature Opportunities` section to output (only if HIGH/MEDIUM items exist)

**New output section:**

```
### Feature Opportunities
| Feature | Relevance | Why Relevant | Current State |
|---------|-----------|-------------|---------------|
| <feature name> | HIGH/MEDIUM | <how it applies to our setup> | <what we currently use/do instead> |
```

### Skill: `renovate-pr-processor`

**New Phase 2.5: Feature Opportunities Issue** (between ANALYZE and REPORT)

1. Collect `### Feature Opportunities` sections from all analyzer outputs
2. Filter to HIGH/MEDIUM relevance only (LOW already excluded by agent)
3. If any found, create a separate GitHub issue:

```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "feat(deps): feature opportunities from renovate batch YYYY-MM-DD" \
  --label "enhancement" \
  --body "<consolidated feature table with PR references>"
```

4. If none found, skip (no empty issue)
5. Reference the feature issue in Phase 5 summary

**Phase 3 (REPORT) change:** Add a "Feature Opportunities" column or note in the summary table pointing to the feature issue.

**Phase 5 (SUMMARY) change:** Include feature opportunities issue link in final report posted to tracking issue.

### Reference: `analysis-patterns.md`

**New section: Feature Opportunity Signals**

Guidance for identifying notable features from changelogs:
- Keywords: "added", "new feature", "now supports", "introducing", "enabled by default"
- Relevance matching patterns (similar structure to breaking change assessment patterns)
- Architecture-aware matching: map deployed CRDs/components to feature categories

## What Does NOT Change

- SAFE/RISKY/UNKNOWN verdict logic
- Breaking change analysis
- Merge order, validation, rollback flows
- Existing memory tables (false positives, repo mappings, etc.)
- The feature evaluation is purely additive
