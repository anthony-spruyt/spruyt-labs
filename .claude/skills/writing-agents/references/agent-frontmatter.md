# Agent Frontmatter Field Reference

| Field | Format | Notes |
|-------|--------|-------|
| `name` | lowercase, numbers, hyphens | Max 64 chars. No reserved words ("anthropic", "claude") |
| `description` | string, max 1024 chars | What + when. See [Description Field](../SKILL.md#description-field) |
| `model` | `opus` / `sonnet` / `haiku` | Optional. See `project-patterns.md` Section 2 for selection guide |
| `tools` | list of tool names | Optional. Omit for all tools. Prefer least privilege |
| `disallowedTools` | list of tool names | Optional. Block specific tools |
| `permissionMode` | string | Optional. Permission level for the agent |
| `maxTurns` | integer | Optional. Limit agentic turns |
| `skills` | list of skill names | Optional. Skills available to the agent |
| `mcpServers` | list of server names | Optional. MCP servers available |
| `hooks` | hook config object | Optional. Agent-specific hooks |
| `memory` | `project` | Optional. Enables agent memory directory |
| `background` | boolean | Optional. Run in background |
| `isolation` | `worktree` | Optional. Run in isolated worktree |
