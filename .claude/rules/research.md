# Research Priority

> **NEVER skip steps. NEVER use WebSearch before exhausting other options.**

| Step | Tool         | Use For                | Example                                            |
| ---- | ------------ | ---------------------- | -------------------------------------------------- |
| 1    | **Context7** | Library/tool docs      | `resolve-library-id` → `get-library-docs`          |
| 2    | **GitHub**   | Issues, PRs, code      | `gh search issues "error" --repo org/repo`         |
| 3    | **Codebase** | Existing patterns      | Grep, Glob, Read                                   |
| 4    | **WebFetch** | Official docs URLs     | raw.githubusercontent.com, allowed docs.\* domains |
| 5    | **WebSearch**| LAST RESORT ONLY       | Only after steps 1-4 fail                          |

## Research Decision Flow

1. **Library/tool question?** → Context7 first (`resolve-library-id`)
   - Found → `get-library-docs`
   - Not found → proceed to step 2
2. **Has GitHub repo?** → `gh` CLI
   - `gh search issues "topic" --repo org/repo`
   - `gh issue list --repo org/repo --search "topic"`
   - For raw files: WebFetch `raw.githubusercontent.com/...`
3. **Official docs URL known?** → WebFetch (allowed domains only)
4. **All above failed?** → WebSearch (state why others failed first)

## Context7 Auto-Fetch Criteria

Auto-fetch (no need to ask):
- Core infrastructure: Flux, Kubernetes, Helm, Cilium, Traefik, Rook, Talos
- Deployed in cluster: check `cluster/apps/` for what's installed
- Common DevOps tools: Terraform, Ansible, cert-manager, external-dns

Ask before resolving:
- Niche/unfamiliar libraries
- Ambiguous names (multiple projects with same name)
- Tools not in above categories

## When Context7 Doesn't Have the Library

1. Check GitHub → `gh issue list --repo org/repo --search "topic"`
2. Fetch README → WebFetch `raw.githubusercontent.com/.../README.md`
3. Only then → WebSearch, explaining: "Context7 and GitHub don't have X, using web search"

## Wrong vs Correct Pattern

```text
# BAD: Jumping to WebSearch
User: "Does Technitium support SSO?"
Wrong: WebSearch("Technitium SSO")  - NEVER do this first

# CORRECT:
1. Context7: resolve-library-id("Technitium")  - Not found
2. GitHub: gh issue list --repo TechnitiumSoftware/DnsServer --search "SSO"
3. WebFetch: raw.githubusercontent.com/.../README.md
4. WebSearch: Only if all above fail
```
