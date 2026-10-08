---
paths: [renovate.json, renovate-overrides.json5]
---

# Renovate Configuration

Config is centralized in [`anthony-spruyt/repo-operator`](https://github.com/anthony-spruyt/repo-operator) (`.github/renovate/`). This repo's root `renovate.json` only extends presets from there and is synced by repo-operator; don't edit it.

Repo-specific overrides (extra `ignorePaths`, `packageRules`) go in root `renovate-overrides.json5`, which `renovate.json` extends as a `local>` preset. repo-operator creates that file once; after that it is owned here. Cross-repo changes go in `repo-operator`.

## Helm Registries

Renovate auto-detects Helm registry URLs from `HelmRepository` resources in `cluster/flux/meta/repositories/helm/`. No manual registry config needed.

## Testing

```bash
renovate-config-validator --strict renovate.json renovate-overrides.json5
task dev-env:renovate-dry-run
```

> `github>` presets resolve from `repo-operator`'s default branch via API, not local files.

After push: trigger via Dependency Dashboard issue, check [Mend logs](https://developer.mend.io/github/anthony-spruyt/spruyt-labs).

## Troubleshooting

| Issue                             | Solution                                            |
| --------------------------------- | --------------------------------------------------- |
| Dependencies not detected         | Check managerFilePatterns in repo-operator managers |
| Grouping not working              | Check matchPackageNames in repo-operator groups     |
| `Failed to look up custom.*`      | Check transform template or URL issues              |
| `Response has failed validation`  | JSONata output format wrong                         |
| `Expected array, received object` | Use `$map()` for array outputs in transforms        |
