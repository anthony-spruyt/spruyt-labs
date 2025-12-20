# Renovate Configuration Standards

## Purpose

This rule establishes standards for maintaining the Renovate configuration in the spruyt-labs repository. It ensures that dependency updates are managed efficiently, safely, and comprehensively across Helm charts, Kubernetes manifests, Terraform, and other dependency types used in the homelab infrastructure.

## Standards

### Regular Maintenance Tasks

1. **Quarterly Reviews**: Review all Renovate configuration files quarterly to ensure they reflect current repository structure, dependency patterns, and best practices.

2. **Registry Updates**: Monitor Helm registries for deprecations, URL changes, or new registry introductions; update registryUrls arrays as needed.

3. **Grouping Audits**: Review package groupings to ensure related components (operators and their CRDs, charts and images) are updated together; add new groupings for newly introduced related packages.

4. **Stability Monitoring**: Monitor update success rates, system stability after deployments, and adjust stabilityDays settings based on component criticality and update history.

5. **Manager Coverage**: Ensure all dependency types and file patterns in the repository have appropriate manager configurations, including regex managers for custom formats.

### When to Update Helm Registries

Update Helm registries in `.github/renovate/helm.json5` when:

- Adding new Helm charts from registries not currently configured
- Registries change URLs or deprecate old URLs
- New OCI registries are introduced for charts
- Quarterly reviews identify inaccessible or outdated registry URLs
- New chart repositories are needed for infrastructure components

### How to Add New Groupings

To add new package groupings in `.github/renovate/groups.json5`:

1. Identify related packages that should be updated together (e.g., operator and its CRDs, chart and associated images)
2. Define groupName, matchPackagePatterns, and matchDatasources
3. Set separateMinorPatch: true for safety and granular update control
4. Add stabilityDays if needed for critical infrastructure components
5. Include appropriate commitMessageTopic for clear PR descriptions
6. Validate the configuration with renovate-config-validator before committing

### Monitoring Stability Settings

- Review PR success rates and system stability after dependency updates
- Adjust stabilityDays based on component criticality (higher for core infrastructure like Cilium, cert-manager)
- Use separateMinorPatch for all groupings to allow independent minor and patch updates
- Monitor for failed updates and adjust configurations or stability settings accordingly
- Document stability decisions in PR descriptions or commit messages

### Ensuring Manager Coverage

- Regularly audit repository for new file types, dependency patterns, or custom formats
- Add or update regex managers in `regex-managers.json5` for custom dependency formats
- Ensure fileMatch patterns in all manager configurations cover all relevant directories and file types
- Test manager configurations with Renovate dry-runs to verify dependency detection
- Update customManagers.json5 when new annotation patterns are introduced

## Procedures

### Updating Helm Registries

1. **Identify Need**: Determine if new registry is required based on new charts or registry changes
2. **Locate Configuration**: Open `.github/renovate/helm.json5`
3. **Add Registry**: Add new registry entry with name and registryUrls
4. **Validate**: Run renovate-config-validator to check syntax
5. **Commit**: Submit changes with descriptive commit message

### Adding Package Groupings

1. **Identify Packages**: Find related packages requiring coordinated updates
2. **Edit Groups File**: Modify `.github/renovate/groups.json5`
3. **Define Group**: Add group object with required properties
4. **Set Stability**: Configure stabilityDays for critical components
5. **Validate Configuration**: Use renovate-config-validator
6. **Test Grouping**: Run dry-run to verify package matching
7. **Document**: Update PR description with grouping rationale

### Monitoring and Adjusting Stability

1. **Review Updates**: Check recent Renovate PRs for success/failure rates
2. **Assess Stability**: Monitor cluster health after updates
3. **Adjust Settings**: Modify stabilityDays in group configurations
4. **Document Changes**: Record stability decisions in commit messages
5. **Schedule Reviews**: Plan quarterly configuration audits

## Practical Configuration Examples

This section provides concrete examples of Renovate configurations commonly used in the spruyt-labs repository.

### Helm Registry Configuration Example

```json5
// .github/renovate/helm.json5
{
  helm: {
    registryUrls: [
      "https://charts.bitnami.com/bitnami",
      "https://grafana.github.io/helm-charts",
      "https://prometheus-community.github.io/helm-charts",
      "https://kubernetes.github.io/ingress-nginx",
      "https://cert-manager.io/",
      "https://fluxcd-community.github.io/helm-charts",
      "https://rook.github.io/rook/",
      "https://victoriametrics.github.io/helm-charts/",
      "https://cloudnative-pg.github.io/charts",
      "https://external-secrets.io",
    ],
  },
}
```

### Package Grouping Examples

```json5
// .github/renovate/groups.json5
{
  groups: {
    cilium: {
      description: "Group Cilium operator and CRDs together",
      matchPackagePatterns: ["^cilium"],
      matchDatasources: ["helm"],
      separateMinorPatch: true,
      stabilityDays: 7,
      commitMessageTopic: "cilium",
    },
    "cert-manager": {
      description: "Group cert-manager components",
      matchPackagePatterns: ["^cert-manager"],
      matchDatasources: ["helm"],
      separateMinorPatch: true,
      stabilityDays: 3,
      commitMessageTopic: "cert-manager",
    },
    "victoria-metrics": {
      description: "Group VictoriaMetrics observability stack",
      matchPackagePatterns: ["^victoria"],
      matchDatasources: ["helm"],
      separateMinorPatch: true,
      stabilityDays: 5,
      commitMessageTopic: "victoria-metrics",
    },
  },
}
```

### Custom Regex Managers for Non-Standard Dependencies

```json5
// .github/renovate/regex-managers.json5
{
  regexManagers: [
    {
      description: "Update Talos image versions in schematics",
      fileMatch: ["talos/.*\\.yaml$"],
      matchStrings: [
        '# renovate: datasource=docker depName=(?<depName>.*?)\\s+version: "(?<currentValue>.*?)"',
      ],
      datasourceTemplate: "docker",
    },
    {
      description: "Update Kubernetes API versions in CRDs",
      fileMatch: ["cluster/crds/.*\\.yaml$"],
      matchStrings: ["apiVersion: (?<depName>.*?)/(?<currentValue>.*)"],
      datasourceTemplate: "kubernetes-api",
    },
    {
      description: "Update Go module versions in Dockerfiles",
      fileMatch: ["Dockerfile.*"],
      matchStrings: ["FROM golang:(?<currentValue>.*?) AS"],
      datasourceTemplate: "docker",
      depNameTemplate: "golang",
    },
    {
      description: "Update Flux OCI repository tags",
      fileMatch: ["cluster/flux/.*\\.yaml$"],
      matchStrings: [
        "tag: (?<currentValue>.*?) # renovate: datasource=(?<datasource>.*?) depName=(?<depName>.*?)",
      ],
    },
  ],
}
```

### Custom Managers for Annotation-Based Updates

```json5
// .github/renovate/customManagers.json5
{
  customManagers: [
    {
      description: "Update Helm chart versions with custom annotations",
      customType: "helm",
      fileMatch: ["cluster/apps/.*\\.yaml$"],
      datasourceTemplate: "helm",
      depNameTemplate: "{{ .chart.name }}",
      currentValueTemplate: "{{ .chart.version }}",
      extractVersionTemplate: "^v?(?<version>.*)$",
    },
    {
      description: "Update Docker image tags in Kubernetes manifests",
      customType: "docker",
      fileMatch: ["cluster/apps/.*\\.yaml$"],
      datasourceTemplate: "docker",
      depNameTemplate: "{{ .image.repository }}",
      currentValueTemplate: "{{ .image.tag }}",
      extractVersionTemplate: "^(?<version>.*)$",
    },
  ],
}
```

## Validation

This section provides detailed instructions for validating Renovate configuration locally to ensure changes are valid before committing. Since Renovate executes in GitHub Actions, local dry-run testing is optional but recommended for complex changes. Local validation primarily focuses on syntax and schema checking using `renovate-config-validator`. Always run `renovate-config-validator` before committing configuration changes. Refer to the [Renovate Dependency Management section in README.md](../README.md#renovate-dependency-management) for integration with repository workflow.

### Configuration Validation

1. **JSON5 Syntax Check**: Validate all Renovate configuration files for syntax errors:

   ```bash
   renovate-config-validator .github/renovate/*.json5
   ```

   Expected output: No errors reported for valid JSON5 syntax.

2. **Schema Validation**: Use Renovate's built-in validation to check configuration against the schema:

   ```bash
   renovate-config-validator .github/renovate/
   ```

   Expected output: Configuration is valid message.

3. **File Pattern Verification**: Ensure fileMatch patterns in manager configurations cover intended directories:
   ```bash
   find . -name "*.yaml" -o -name "*.yml" | head -10  # Verify YAML files are detected
   find cluster/ -name "*.yaml" | grep -E "(chart|values)" | head -5  # Check Helm-related files
   ```

### Dry-Run Tests

Dry-run testing is primarily intended for GitHub Actions CI/CD pipelines to validate configuration changes before deployment. Local dry runs are optional and useful for complex configuration changes or troubleshooting, but not required for routine validation.

1. **Local Dry Run**: Test Renovate configuration against the repository without creating PRs:

   ```bash
   renovate --dry-run --log-level debug --require-config .github/renovate/
   ```

   Expected output: Dependency detection results and proposed updates logged without execution.

2. **Specific Manager Testing**: Test individual manager configurations:

   ```bash
   renovate --dry-run --require-config .github/renovate/helm.json5 --log-level info
   renovate --dry-run --require-config .github/renovate/groups.json5 --log-level info
   ```

3. **Repository Scan**: Verify dependency detection across the entire repository:
   ```bash
   renovate --dry-run --print-config | jq '.repositories[] | select(.repository == ".") | .config'
   ```
   Expected output: Complete configuration object showing detected managers and settings.

### Dependency Detection Verification

1. **Helm Chart Detection**: Confirm Helm charts are properly detected:

   ```bash
   grep -r "chart:" cluster/apps/ | head -5  # Find chart references
   renovate --dry-run | grep -i "helm"
   ```

   Expected output: HelmRelease and chart dependencies listed in dry-run output.

2. **Docker Image Detection**: Verify container image dependencies are found:

   ```bash
   grep -r "image:" cluster/apps/ | grep -v "imagePullPolicy" | head -5
   renovate --dry-run | grep -i "docker\|container"
   ```

3. **Custom Regex Patterns**: Test regex managers for custom dependency formats:

   ```bash
   renovate --dry-run --require-config .github/renovate/regex-managers.json5
   ```

   Expected output: Custom dependencies detected according to regex patterns.

4. **Grouping Validation**: Ensure package groupings work as expected:
   ```bash
   renovate --dry-run --require-config .github/renovate/groups.json5 | grep -A 5 -B 5 "group"
   ```
   Expected output: Packages grouped according to matchPackagePatterns.

### Troubleshooting Common Issues

1. **Configuration Syntax Errors**: If validation fails with JSON5 errors:

   - Check for missing commas, quotes, or brackets
   - Use an online JSON5 validator for complex configurations
   - Compare with working examples in the Renovate documentation
   - Validate JSON5 syntax: `renovate-config-validator .github/renovate/*.json5`

2. **Missing Dependencies**: If expected dependencies are not detected:

   - Verify fileMatch patterns cover the correct file paths
   - Check regex patterns in regex-managers.json5 for accuracy
   - Ensure datasource is correctly specified for the dependency type
   - Run `find . -name "*.yaml" | xargs grep -l "<dependency>"` to locate files

3. **Incorrect Grouping**: If packages are not grouped as expected:

   - Review matchPackagePatterns for proper regex syntax
   - Check matchDatasources to ensure they align with dependency types
   - Test individual group configurations separately

4. **Registry Access Issues**: If Helm registries are inaccessible:

   - Verify registryUrls are correct and accessible
   - Check for authentication requirements in private registries
   - Test registry connectivity: `helm repo add test <url> && helm repo update`

5. **Failed Updates in Production**: If Renovate PRs cause cluster issues:

   - Review PR description for stability days and testing recommendations
   - Check cluster health: `kubectl get nodes` and `flux get kustomizations -A`
   - Roll back by reverting the merge commit
   - Adjust stabilityDays in group configurations for problematic components
   - Document the issue in the PR for future reference

6. **Custom Regex Manager Issues**: If regex patterns don't match:

   - Test regex patterns with online regex testers
   - Use `grep -r "<pattern>" .` to verify file content matches
   - Check capture groups (?<depName>, ?<currentValue>) are correctly named
   - Validate datasourceTemplate matches the dependency type
   - Example debug: `grep -r "datasource=docker" cluster/ | head -5`

7. **Authentication Problems**: If Renovate can't access private registries:

   - Ensure GitHub secrets are configured for private registries
   - Check hostRules in renovate.json for authentication
   - Verify token permissions for repository access
   - Test authentication manually with curl or helm commands

8. **Version Pinning Issues**: If versions aren't updating as expected:

   - Check for version constraints in package files
   - Verify stabilityDays hasn't blocked recent updates
   - Review ignoreDeps or packageRules that might exclude updates
   - Use Renovate dashboard to see why updates are blocked

## Enforcement

- Renovate configuration changes must pass mega-linter checks
- New dependency types require appropriate manager configuration before introduction to the repository
- Failed Renovate updates require review and potential configuration adjustments
- Quarterly audits must be documented with findings and actions taken
- Pull requests modifying Renovate configuration require review for compliance with these standards

## Related Rules

- [documentation_standards.md](documentation_standards.md) — for documenting Renovate configuration changes and update procedures
