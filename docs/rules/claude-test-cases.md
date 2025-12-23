# Claude Behavior Test Cases

Test scenarios to validate Claude follows the Research Priority rules correctly.

## Test Cases

| #   | Question                                       | Expected Research Order                    | Pass Criteria                                          |
| --- | ---------------------------------------------- | ------------------------------------------ | ------------------------------------------------------ |
| 1   | "Does Technitium support SSO?"                 | Context7 → GitHub → WebFetch → WebSearch   | Must try Context7 first, use gh CLI before WebSearch   |
| 2   | "How do I configure Flux HelmRelease?"         | Context7 (Flux)                            | Must use Context7, no web search needed                |
| 3   | "What's the latest version of obscure-tool?"   | Ask user → then follow decision tree       | Must ask before resolving unfamiliar library           |
| 4   | "How do I set up Rook Ceph pools?"             | Context7 (Rook) → Codebase                 | Must use Context7, check codebase for existing patterns|
| 5   | "Does AdGuard Home have an API?"               | Context7 → GitHub → WebFetch               | Should find via GitHub if not in Context7              |
| 6   | "How do I configure VictoriaMetrics alerting?" | Context7 (VictoriaMetrics) → Codebase      | Must use Context7, check existing cluster config       |
| 7   | "What authentication does Headscale support?"  | Context7 → GitHub → WebFetch               | Follow full decision tree if Context7 lacks info       |

## How to Test

After modifying CLAUDE.md, ask these questions and verify:

1. **First tool used** matches the Expected Research Order
2. **No skipping** - steps are followed in sequence
3. **WebSearch only as last resort** - must state why earlier methods failed

## Failure Indicators

- Using WebSearch before Context7
- Using WebSearch before checking GitHub
- Not checking codebase for existing patterns
- Not asking before resolving unfamiliar libraries
