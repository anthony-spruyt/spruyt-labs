---
paths: ["**/*.md"]
---

# Documentation Standards

## Code Block Standards

1. **Language identifiers required**: Use triple backticks with identifiers (`yaml`, `bash`, `json`, `text`)
2. **Consistent indentation**: 2 spaces for YAML, 4 spaces for JSON
3. **Line length**: Max 120 characters for readability
4. **No raw code**: All commands and configs must be in code blocks

## Content Standards

1. **Accuracy**: Documentation must reflect current state
2. **No generic commands**: Do not document standard kubectl/flux commands (get pods, logs, reconcile). Only document component-specific operations that are non-obvious
3. **Consistency**: Follow the README template for components
4. **GitOps-first**: Prefer editing manifests and reconciling over manual kubectl apply

## Accuracy Requirements

1. **Component names**: Must match exactly what's in release.yaml and Helm chart
2. **Namespaces**: Must match ks.yaml targetNamespace
3. **Dependencies**: Must list actual dependencies from ks.yaml dependsOn

## README Template

Use template from `docs/templates/readme_template.md` for new component docs.

Required sections:
- Overview (mention priority tier)
- Prerequisites (list dependsOn items)
- Troubleshooting (only non-obvious, component-specific issues)
- References (official docs links)

## Maintenance

- Update docs when repository changes affect accuracy
- New app components require README.md before commit/merge
