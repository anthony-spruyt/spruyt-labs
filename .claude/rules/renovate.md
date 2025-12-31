---
paths: .github/renovate/**, .taskfiles/**, cluster/**
---

# Renovate Configuration

Renovate automates dependency updates. Configuration files are in `.github/renovate/`.

## Helm Registries

Renovate's Flux manager auto-detects Helm registry URLs from `HelmRepository` resources. No manual registry configuration needed.

When adding new Helm charts:
1. Create a `HelmRepository` in `cluster/flux/meta/repositories/helm/`
2. Reference it in your `HelmRelease` via `sourceRef`
3. Renovate auto-resolves the registry URL

## Shell Script Annotations

For install scripts in `.taskfiles/`, use Renovate annotations:

```bash
#!/bin/bash
# renovate: depName=kubernetes/kubernetes datasource=github-releases
VERSION="v1.35.0"
```

**Common datasources:**
- `github-releases` - GitHub release tags
- `docker` - Container image tags

| Tool    | depName               | datasource      |
| ------- | --------------------- | --------------- |
| kubectl | kubernetes/kubernetes | github-releases |
| helm    | helm/helm             | github-releases |
| velero  | vmware-tanzu/velero   | github-releases |

## Package Groupings

Edit `.github/renovate/groups.json5`:

```json5
{
  packageRules: [
    {
      groupName: "cilium",
      matchPackagePatterns: ["^cilium"],
      matchDatasources: ["helm"],
      separateMinorPatch: true,
      minimumReleaseAge: "7 days",
    },
  ],
}
```

## Testing Config Changes

```bash
# Validate before commit
renovate-config-validator --strict .github/renovate.json5
renovate-config-validator --strict .github/renovate/customDatasources.json5
```

After push:
1. Trigger manual run via Dependency Dashboard issue
2. Check [Mend Renovate logs](https://developer.mend.io/github/anthony-spruyt/spruyt-labs)
3. Verify expected PRs are created

## Troubleshooting

| Issue                          | Solution                                         |
| ------------------------------ | ------------------------------------------------ |
| Dependencies not detected      | Check fileMatch patterns cover the file paths    |
| Grouping not working           | Verify matchPackagePatterns regex syntax         |
| Updates blocked                | Check minimumReleaseAge or Dependency Dashboard  |
| Cluster issues after update    | Revert merge commit, increase minimumReleaseAge  |
| `Failed to look up custom.*`   | Check transform template or URL issues           |
| `Response has failed validation` | JSONata output format wrong                    |
| `Expected array, received object` | Use `$map()` for array outputs in transforms |
