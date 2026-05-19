---
name: block-individual-linters
enabled: true
event: bash
pattern: (^|[;&|]\s*)(yamllint|shellcheck|markdownlint|actionlint|tflint|gitleaks|secretlint|trivy|lychee)\b
action: block
---

**BLOCKED: Individual linter commands are not allowed**

You attempted to run an individual linter directly. This is forbidden.

**Use MegaLinter instead:**

```bash
task dev-env:lint
```

**Why?**

- MegaLinter runs ALL linters with consistent configuration
- Output goes to `.output/` directory for detailed reports
- Prevents inconsistent or partial linting

**After running MegaLinter:**

1. Check exit code for pass/fail
2. If failures, read files in `.output/` to see specific errors
3. Use the Read tool on `.output/` files to investigate

See `.claude/agents/qa-validator.md` section "4. Local Linting (MegaLinter)" for details.
