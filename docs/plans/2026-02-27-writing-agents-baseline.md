# Writing Agents Skill — Baseline Test Results

## Test Setup

A subagent was given this prompt with NO writing-agents skill available:

> "Optimize the agent at `.claude/agents/qa-validator.md` to improve token efficiency and follow best practices. The agent is 569 lines — reduce it while maintaining quality."

## Results

| Metric | Original | Baseline Optimized |
|--------|----------|--------------------|
| Lines | 569 | 277 |
| Reduction | — | 51% |

## What the Baseline Got Right

1. **Identified duplicate context from CLAUDE.md/rules** — Correctly noted that secrets handling, research priority, and validation flow are inherited from `.claude/rules/`. Replaced with references.
2. **Removed verbose teaching examples** — Cut Context7 worked examples (~40 lines) and sanity check BAD/Better examples (~30 lines).
3. **Removed emotional emphasis slogans** — Cut "TRUST NO ONE. VERIFY EVERYTHING." heading and explanatory paragraph.
4. **Preserved structural integrity** — All 12 validation steps kept, output format preserved, handoff protocol maintained, self-improvement workflow intact.
5. **Left frontmatter untouched** — Correctly identified it as routing information with high change risk.
6. **Consolidated defensive redundancy** — Merged sections that said the same thing in different ways.

## What the Baseline Missed

### 1. Emphasis Calibration for Claude 4.5/4.6 (MISSED ENTIRELY)

The optimized version still freely uses aggressive emphasis: "MANDATORY", "MUST", "NEVER", "NOT optional", bold markers throughout. Per Anthropic's Claude 4.5/4.6 best practices, these cause overtriggering. The agent removed the worst slogans but did NOT systematically soften emphasis language.

**Examples still present in baseline output:**
- "MANDATORY" in 3 section headers
- "MUST" in 4 places
- "NEVER" in 7 places (some appropriate for hard gates, many not)
- "NOT optional" as emphasis

**Rationalization used:** None — the agent simply didn't consider this. It removed "emotional emphasis" but conflated that with only the most extreme slogans, not the pervasive CAPS/bold pattern.

### 2. No Progressive Disclosure / Content Extraction (MISSED ENTIRELY)

The agent compressed content inline but never considered extracting heavy reference material to separate files. The output format template (~40 lines), Context7 verification table, and sanity check table could live in reference files loaded on demand, keeping the main prompt leaner.

**Rationalization used:** The agent focused on inline compression (shorter sentences, merged sections) as the only optimization strategy. File extraction wasn't mentioned at all.

### 3. Over-Explanations for Opus (PARTIALLY ADDRESSED)

The agent removed some teaching examples but kept explanatory text for things Opus already knows:
- Detailed bash detection logic with comments (Opus can write bash)
- Explaining what dry-run validation does (Opus knows kubectl)
- "YAML/JSON syntax is handled by MegaLinter in Step 4" — Opus can read the step ordering

**Rationalization used:** "Every step represents a distinct validation category." True, but the steps don't need to explain what the tools do.

### 4. Mechanism Confusion (INCORRECT REASONING)

The agent stated that `memory: project` means the agent "inherits all `.claude/rules/` files." This is wrong. All agents inherit CLAUDE.md and rules by default (it's how Claude Code works). `memory: project` gives access to agent-specific memory files in `.claude/agent-memory/`. The optimization conclusions were correct (rules are inherited, so don't duplicate) but the stated mechanism was wrong.

### 5. Word Count Not Checked

The plan mentions checking word count as a sizing metric alongside line count. The baseline only measured lines. Word count matters because a 277-line file with dense paragraphs may have more tokens than a 400-line file with sparse formatting.

### 6. Frontmatter Not Analyzed for Anti-Patterns

The agent praised the frontmatter as "exceptionally well-written" but didn't analyze whether the description contains workflow summaries (an anti-pattern where Claude follows the description shortcut instead of reading the full system prompt body). In this case the qa-validator description is actually fine — it has triggering conditions and examples, not workflow — but the baseline didn't evaluate this.

## Rationalizations Documented

| Rationalization | Translation |
|-----------------|-------------|
| "LLMs respond to clear instructions, not motivational slogans" | Correct for slogans, but then didn't address systematic emphasis calibration |
| "The agent can infer specific instances from the patterns" | Justified removing examples but didn't consider whether Opus needs ANY guidance on those patterns |
| "Every step represents a distinct validation category" | True, but used to avoid trimming explanatory text within steps |
| "Frontmatter is exceptionally well-written" | Didn't critically analyze, just complimented |
| "Changes there carry higher risk and should be tested separately" | Avoided frontmatter analysis entirely |

## Key Gaps the Skill Must Address

1. **Systematic emphasis calibration** — The skill must explicitly guide softening CRITICAL/MUST/NEVER for Claude 4.5/4.6, not just removing slogans
2. **Progressive disclosure via file extraction** — The skill must teach extracting heavy content to reference files, not just inline compression
3. **Over-explanation awareness for Opus** — The skill must distinguish between "what to do" (keep) and "why/how this works" (remove for Opus)
4. **Word count as sizing metric** — Line count alone is insufficient
5. **Description field analysis** — The skill must guide checking for workflow-in-description anti-pattern
