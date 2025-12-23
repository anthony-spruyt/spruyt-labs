# Renovate Configuration Standards

## Overview

Renovate automates dependency updates for Helm charts, Kubernetes manifests, Terraform, and other components. Configuration files are in `.github/renovate/`.

## How Helm Registries Work

Renovate's Flux manager auto-detects Helm registry URLs from `HelmRepository` resources. No manual registry configuration needed.

When adding new Helm charts:

1. Create a `HelmRepository` in `cluster/flux/meta/repositories/helm/`
2. Reference it in your `HelmRelease` via `sourceRef`
3. Renovate auto-resolves the registry URL

## Adding Package Groupings

Edit `.github/renovate/groups.json5` to group related packages:

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

## Maintenance

- **Quarterly**: Review config files match current repo structure
- **Groupings**: Ensure related packages (operators + CRDs, charts + images) update together
- **Stability**: Adjust `minimumReleaseAge` for critical components (Cilium, cert-manager)
- **Coverage**: Add regex managers for custom dependency formats

## Testing Config Changes

### Before Committing

```bash
# Validate all renovate configs
renovate-config-validator --strict .github/renovate.json5

# Validate specific config files
renovate-config-validator --strict .github/renovate/customDatasources.json5
```

### After Pushing

1. Trigger a manual Renovate run via the Dependency Dashboard issue
2. Check the [Mend Renovate logs](https://developer.mend.io/github/anthony-spruyt/spruyt-labs) for errors
3. Verify expected PRs are created or dependencies are detected

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

## Related

- [Maintenance - Renovate section](../maintenance.md#renovate-dependency-management)
