---
name: spec-review
description: >
  Architectural and technical review of a design spec. Spawns a subagent reviewer
  that verifies spec claims against live cluster state and deployed manifests, checks
  library/framework docs via Context7, and produces severity-ranked findings.
  Use when iterating on spec quality before implementation planning.
argument-hint: <spec-file-path>
arguments: [spec]
---

# Spec Review

You are reviewing the spec at `$spec`.

## Instructions

1. Read the review brief at [review-brief.md](review-brief.md)
2. Read the full spec at `$spec`
3. Spawn a general-purpose subagent to perform the review. Brief it with:
   - The full review brief contents
   - The spec file path to review
   - Instruction to use Context7 for library/framework validation
   - Instruction to search `cluster/apps/` for deployed manifests to verify spec claims
   - Instruction to use MCP kubectl tools to check live cluster state where manifests alone are insufficient
   - Instruction to cross-reference findings against the spec's own risks table, phase checklists, and tradeoff callouts before flagging — do not raise concerns the spec already addresses
4. After receiving findings, present results organized by severity
5. Offer to update the spec based on findings

## Rules

- **NEVER append review notes, summaries, or review round logs to the spec file.** The spec is the design document — not a review journal. Findings go in conversation output only.
- Only edit the spec to fix actual issues identified in findings (incorrect claims, missing sections, design gaps). Each edit should improve the spec's content, not add meta-commentary about the review process.
