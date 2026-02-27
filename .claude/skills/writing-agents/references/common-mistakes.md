# Common Mistakes

| Mistake | Fix |
|---------|-----|
| Workflow summary in description | Brief capability + triggering conditions only. Put workflow in body |
| CRITICAL/MANDATORY/NEVER overuse | Normal language. Claude 4.5/4.6 overtriggers on aggressive emphasis |
| Explaining Kubernetes/YAML/Git basics | Remove. Opus knows these |
| Copying CLAUDE.md secret rules | Remove. Agent inherits project rules |
| 500+ line system prompt | Extract reference content to files. Target < 300 lines |
| All tools inherited | Restrict to what's needed (least privilege) |
| No output format specified | Add structured output template |
| No examples in description | Add 1-2 `<example>` blocks with context/user/assistant/commentary |
| Magic commands without explanation | Add brief comment explaining why (right altitude) |
| No self-improvement for high-touch agents | Add memory pattern if agent runs frequently |
| Vague scope enabling unnecessary subagent spawning | Add "Only make changes directly requested." Prefer Grep/Read over subagents for lookups |
| Multi-goal agent | Split into focused agents. One clear goal, input, output per agent |
| No confirmation gates for destructive actions | Add explicit guidance on which actions need user confirmation |
| Independent checks run sequentially | Mark parallel groups: "Run in parallel: [list]. After those pass: [list]" (see `references/anthropic-best-practices.md` Section 6) |
| No feedback loop for validation agents | Add validator -> fix -> retry pattern with structured output (file paths, line numbers, exact fixes) |
| Sequential workflow with no halt conditions | Add "stop on error" at each step. Do not proceed if intermediate step fails |
