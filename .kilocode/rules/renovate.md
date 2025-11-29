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
6. Test the grouping with a Renovate dry-run before committing

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

## Testing and Validation

This section provides detailed instructions for testing Renovate configuration locally to ensure changes are valid and effective before committing. Refer to the [Renovate Dependency Management section in README.md](../README.md#renovate-dependency-management) for integration with repository workflow.

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

5. **Dry-Run Failures**: If dry-run exits with errors:

   - Increase log level: `--log-level debug` for more details
   - Check for network connectivity issues
   - Verify Git repository access and credentials
   - Ensure all required environment variables are set

6. **Performance Issues**: If dry-run takes too long:
   - Limit scope with `--include-paths` for specific directories
   - Use `--dry-run` with `--print-config` to debug configuration loading
   - Check for overly broad fileMatch patterns causing excessive file scanning

## Enforcement

- Renovate configuration changes must pass mega-linter checks
- New dependency types require appropriate manager configuration before introduction to the repository
- Failed Renovate updates require review and potential configuration adjustments
- Quarterly audits must be documented with findings and actions taken
- Pull requests modifying Renovate configuration require review for compliance with these standards

## Related Rules

- [documentation_standards.md](documentation_standards.md) — for documenting Renovate configuration changes and update procedures

## Changelog

- 2025-11-29 · Initial creation of Renovate configuration standards rule.
