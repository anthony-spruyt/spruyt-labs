# Anthropic Best Practices for Agent Authoring

Reference material from official Anthropic documentation. Each principle includes actionable guidance and source URL.

## Contents

01. [Token Efficiency](#1-token-efficiency)
02. [Right Altitude](#2-right-altitude)
03. [Emphasis Calibration](#3-emphasis-calibration)
04. [Scope Creep](#4-scope-creep)
05. [Autonomy and Safety](#5-autonomy-and-safety)
06. [Parallel Execution](#6-parallel-execution)
07. [Progressive Disclosure](#7-progressive-disclosure)
08. [Subagent Design](#8-subagent-design)
09. [Tool Scoping](#9-tool-scoping)
10. [Feedback Loops](#10-feedback-loops)
11. [Stop on Error](#11-stop-on-error)
12. [Don't Over-Explain to Opus](#12-dont-over-explain-to-opus)
13. [Don't Duplicate Inherited Context](#13-dont-duplicate-inherited-context)

______________________________________________________________________

## 1. Token Efficiency

Context is finite. Every token competes with conversation history, other skills, and the actual request. "Context rot" degrades recall as token count grows — this is a performance gradient, not a cliff. Challenge each section: "Does this justify its token cost?" Start minimal, add only when testing reveals gaps.

Source: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents

## 2. Right Altitude

Match specificity to task fragility. High freedom (text guidance) for judgment calls where multiple approaches are valid. Low freedom (exact commands) for fragile, error-prone operations. Think: narrow bridge with cliffs = exact commands; open field = general direction.

Source: https://platform.claude.com/docs/en/docs/agents-and-tools/agent-skills/best-practices

## 3. Emphasis Calibration

Current Claude models follow system prompts closely; emphasis written to fix undertriggering causes overtriggering. Replace "CRITICAL: You MUST use this tool when..." with "Use this tool when...". Keep strong language for safety gates only.

Source: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices

## 4. Scope Creep

If testing shows an agent creating extra files, abstractions, or unrequested flexibility, add a targeted line: "Only make changes that are directly requested." Add it when observed, not by default.

Source: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices

## 5. Autonomy and Safety

Without guidance, an agent may take actions that are hard to reverse — deleting files, force-pushing, posting to external services. Agents performing destructive or externally-visible operations should include confirmation gates. Add explicit guidance on which actions require user confirmation vs. which can proceed autonomously.

Source: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices

## 6. Parallel Execution

State which checks are independent and which depend on earlier results, so independent ones run in parallel. Example: "These checks can run in parallel: [list]. Run these after the above pass: [list]."

Source: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices

## 7. Progressive Disclosure

Main file as overview pointing to detailed materials loaded on demand. Keep main body under 500 lines. Reference files one level deep only (no nested references). Include table of contents in files over 100 lines. Only metadata (name, description) is pre-loaded; SKILL.md loads when triggered; reference files load on demand.

Source: https://platform.claude.com/docs/en/docs/agents-and-tools/agent-skills/best-practices

## 8. Subagent Design

One clear goal, input, output, and handoff rule per agent. Well-scoped tools make it easier for Claude to decide next steps. Minimize tool set overlap. If an agent spawns subagents where a direct lookup would do, say when not to.

Sources: https://claude.com/blog/building-agents-with-the-claude-agent-sdk, https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices

## 9. Tool Scoping

Least privilege. Restrict to essential tools. Read-only agents should not have Write/Edit. Operational agents need Bash. Analysis agents need Read/Grep/Glob. Tools are prominent in Claude's context window, making them the primary actions Claude considers — be conscious about which tools you expose.

Source: https://claude.com/blog/building-agents-with-the-claude-agent-sdk

## 10. Feedback Loops

Run validator -> fix errors -> repeat. This pattern greatly improves output quality. Structure output for the calling agent to parse and act on. Provide exact fixes (file paths, line numbers, corrected code), not vague guidance. Three approaches: rules-based feedback, visual verification, LLM-as-judge.

Sources: https://claude.com/blog/building-agents-with-the-claude-agent-sdk, https://platform.claude.com/docs/en/docs/agents-and-tools/agent-skills/best-practices

## 11. Stop on Error

For sequential multi-step workflows, add explicit termination conditions at each step. If an intermediate step fails, halt execution and report — do not continue to subsequent steps. Example patterns: "Do not proceed if linting fails", "If defrag fails on any node, stop and report." This prevents cascading failures where a broken intermediate state causes worse damage in later steps.

Source: Observed pattern in project agents (qa-validator, etcd-maintenance, cluster-validator)

## 12. Don't Over-Explain to Opus

Claude Opus already knows Kubernetes, YAML, Git, common tools, and standard libraries. Remove explanations of concepts Opus understands. Focus on project-specific context it can't infer. Only add context Claude doesn't already have. Challenge each piece: "Can I assume Claude knows this?"

Source: https://platform.claude.com/docs/en/docs/agents-and-tools/agent-skills/best-practices

## 13. Don't Duplicate Inherited Context

Agents inherit CLAUDE.md and project rules automatically. Don't repeat secret handling rules, git conventions, or workflow constraints already in rules files. Reference them if needed ("follow inherited rules for X"), don't copy them. Once a tool executes deep in history, the raw output doesn't need to persist — discard intermediate outputs once their purpose is served.

Source: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
