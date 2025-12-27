# Add New Workload

Deploy a new application to the cluster following GitOps patterns and conventions.

Run this prompt when adding any new HelmRelease-based workload to the cluster.

---

## Step 1: Gather Requirements

Before implementation, ask the user:

1. **What workload do you want to add?** (name, brief description)
2. **What is the Helm chart source?** (chart name, repository URL, or OCI registry)
3. **What namespace should it use?** (new namespace or existing)
4. **What priority tier?** (see classification criteria below)
5. **Any dependencies?** (databases, secrets, other apps)
6. **Does it need ingress/external access?**
7. **Any specific configuration requirements?**

### Priority Classification Criteria

Reference: [docs/workload-classification.md](../../docs/workload-classification.md)

| Priority Class          | Criteria                                             | CPU Limit Policy |
|-------------------------|------------------------------------------------------|------------------|
| critical-infrastructure | Cluster won't function without it                    | No limit         |
| high-priority           | Essential services, observability, auth              | 5x request       |
| standard                | Business applications (default)                      | 3x request       |
| low-priority            | Internal tools, gaming, hobby projects               | 2x request       |
| best-effort             | Batch jobs, preemptible workloads                    | 1x (= request)   |

---

## Step 2: Research the Helm Chart

Before writing any files, understand the chart:

1. **Find the chart values and schema**:
   - Use Context7: `resolve-library-id` then `get-library-docs`
   - Or fetch raw values.yaml from GitHub: `raw.githubusercontent.com/<org>/<repo>/...`
   - **Check for values.schema.json**: Many charts provide JSON schemas for validation
     - Look for `values.schema.json` in the chart directory
     - Check ArtifactHub page for schema availability
     - GitHub search: `gh api repos/<org>/<repo>/contents/charts/<chart>` to list files
     - **Search other repos for existing schema usage**:
       ```bash
       # Pattern: /yaml-language-server:\s*[^\n]*<name>[^\n]*\.json/
       # Replace <name> with chart name or CR type (e.g., falco, kustomization, helmrelease)
       gh search code 'yaml-language-server' '<name>' '.json' --limit 10
       ```
   - If schema exists, **validate the URL returns HTTP 200** before using:
     ```bash
     curl -sL -o /dev/null -w "%{http_code}" "<schema-url>"
     ```
   - If valid, note URL for values.yaml header (see 4f below)
   - If no schema found, use `# #yaml-language-server: $schema=TODO` (double comment)

2. **Identify key configuration paths**:
   - Where does `priorityClassName` go? (top-level, under `deployment`, under component name?)
   - Where do `resources` go?
   - Where do `tolerations` go?
   - What are the main component names?

3. **Check for dependencies**:
   - Does it need a database? (CNPG cluster)
   - Does it need secrets? (ExternalSecret or SOPS)
   - Does it need PVCs? (StorageClass selection)

4. **Check for special requirements**:
   - Privileged access? (PSA labels on namespace)
   - Host network?
   - Specific node selectors?

---

## Step 3: Create Directory Structure

Standard app structure:

```text
cluster/apps/<namespace>/
├── namespace.yaml              # Namespace with PSA labels
├── kustomization.yaml          # References namespace + app ks.yaml
└── <app>/
    ├── README.md               # Documentation (required)
    ├── ks.yaml                 # Flux Kustomization
    └── app/
        ├── kustomization.yaml  # Kustomize config
        ├── release.yaml        # HelmRelease
        ├── values.yaml         # Helm values
        ├── kustomizeconfig.yaml
        └── [optional files]    # secrets, network policies, etc.
```

For apps in existing namespaces, add to existing kustomization.yaml.

---

## Step 4: Create Files

### 4a. HelmRepository (if new chart source)

**Path**: `cluster/flux/meta/repositories/helm/<name>-charts.yaml`

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/source.toolkit.fluxcd.io/helmrepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: <name>-charts
  namespace: flux-system
spec:
  url: https://<chart-repo-url>
```

Add to `cluster/flux/meta/repositories/helm/kustomization.yaml` (alphabetically).

### 4b. Namespace (if new namespace)

**Path**: `cluster/apps/<namespace>/namespace.yaml`

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: <namespace>
  labels:
    pod-security.kubernetes.io/enforce: baseline  # or privileged if needed
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

PSA Label Guide:
- `baseline` - Default for most workloads
- `privileged` - Required for: eBPF, host networking, privileged containers

### 4c. Namespace Kustomization

**Path**: `cluster/apps/<namespace>/kustomization.yaml`

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./<app>/ks.yaml
```

### 4d. Flux Kustomization

**Path**: `cluster/apps/<namespace>/<app>/ks.yaml`

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app <app-name>
  namespace: flux-system
spec:
  targetNamespace: <namespace>
  path: ./cluster/apps/<namespace>/<app>/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:           # Optional: add if app has dependencies
    - name: <dependency>
  prune: true
  timeout: 5m          # Increase for slow deployments (10m for large apps)
  wait: true
```

### 4e. HelmRelease

**Path**: `cluster/apps/<namespace>/<app>/app/release.yaml`

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <app-name>
spec:
  chart:
    spec:
      chart: <chart-name>
      version: <version>
      sourceRef:
        kind: HelmRepository  # or OCIRepository
        name: <repo-name>
        namespace: flux-system
  valuesFrom:
    - kind: ConfigMap
      name: <app-name>-values
```

### 4f. Helm Values

**Path**: `cluster/apps/<namespace>/<app>/app/values.yaml`

```yaml
---
# yaml-language-server: $schema=<schema-url>  # If schema exists and validated (HTTP 200)
# #yaml-language-server: $schema=TODO         # If no schema available (double # to disable)
# <Priority-tier>: <rationale> (per docs/workload-classification.md)
# CPU limit: <multiplier>x request per <tier> policy

# Priority class - REQUIRED for all workloads
priorityClassName: <priority-class>  # Check chart docs for correct path

# Tolerations if running on control plane
tolerations:
  - effect: NoSchedule
    key: node-role.kubernetes.io/control-plane
    operator: Exists

# Resources - REQUIRED, follow tier CPU limit policy
resources:
  requests:
    cpu: <request>m
    memory: <request>Mi
  limits:
    cpu: <limit>m     # = request * tier multiplier (omit for critical-infrastructure)
    memory: <limit>Mi

# ... app-specific configuration
```

### 4g. App Kustomization

**Path**: `cluster/apps/<namespace>/<app>/app/kustomization.yaml`

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./release.yaml
configMapGenerator:
  - name: <app-name>-values
    namespace: <namespace>
    files:
      - values.yaml
configurations:
  - ./kustomizeconfig.yaml
```

### 4h. Kustomize Config

**Path**: `cluster/apps/<namespace>/<app>/app/kustomizeconfig.yaml`

```yaml
---
nameReference:
  - kind: ConfigMap
    version: v1
    fieldSpecs:
      - path: spec/valuesFrom/name
        kind: HelmRelease
```

### 4i. README

**Path**: `cluster/apps/<namespace>/<app>/README.md`

Use template from [docs/templates/readme_template.md](../../docs/templates/readme_template.md).

Required sections:
- Overview (mention priority tier)
- Prerequisites (list dependsOn items)
- Operation (key kubectl/flux commands)
- Troubleshooting (common issues)
- References (official docs links)

---

## Step 5: Wire Up References

### 5a. Add to top-level apps kustomization

**Path**: `cluster/apps/kustomization.yaml`

Add `- ./<namespace>` to resources list (if new namespace).

### 5b. Update workload classification doc

**Path**: `docs/workload-classification.md`

Add workload to appropriate tier table:

```markdown
| <namespace> | <workload-names> | <rationale> |
```

---

## Step 6: Validate

### 6a. Run linter

```bash
task dev-env:lint
```

Fix any issues before committing.

### 6b. Commit changes

Follow conventional commits:

```bash
git add -A
git commit -m "feat(<namespace>): add <app-name>

<Brief description of what it does>
- <key feature 1>
- <key feature 2>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

### 6c. Post-push validation

After user pushes and Flux reconciles:

```bash
# Check Flux reconciliation
flux get kustomization <app-name>

# Check HelmRelease status
kubectl get hr -n <namespace> <app-name>

# Check pods
kubectl get pods -n <namespace>

# View logs for issues
kubectl logs -n <namespace> -l app.kubernetes.io/name=<app-name> --tail=20
```

---

## Common Patterns

### Apps with Databases (CNPG)

Add CNPG cluster dependency and create database resources:
- Add `dependsOn: [{name: cnpg-operator}]` to ks.yaml
- Create `*-cnpg-cluster.yaml` in app/ directory

### Apps with Secrets

Options:
1. **ExternalSecret** - For secrets stored in external provider
2. **SOPS** - For secrets stored in git (`*-secrets.sops.yaml`)

### Apps with Multiple Components

Create separate Kustomizations in the same ks.yaml:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app myapp
spec:
  path: ./cluster/apps/<namespace>/<app>/app
  ...
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: myapp-ingress
spec:
  path: ./cluster/apps/<namespace>/<app>/ingress
  dependsOn:
    - name: myapp
  ...
```

### Apps Needing ServiceMonitor

Add to values.yaml (check chart docs for exact path):

```yaml
serviceMonitor:
  enabled: true
```

Or create a separate VMServiceScrape resource.

---

## Checklist

Before considering the task complete:

- [ ] HelmRepository created (if new source)
- [ ] Namespace with PSA labels
- [ ] Flux Kustomization with dependsOn
- [ ] HelmRelease pointing to chart
- [ ] values.yaml with priorityClassName and resources
- [ ] YAML schemas added where available (validated HTTP 200)
- [ ] README.md following template
- [ ] Added to cluster/apps/kustomization.yaml
- [ ] Added to docs/workload-classification.md
- [ ] Linter passes
- [ ] Commit with conventional message

---

## References

- [docs/workload-classification.md](../../docs/workload-classification.md) - Priority tiers and CPU limits
- [docs/templates/readme_template.md](../../docs/templates/readme_template.md) - README template
- [docs/rules/documentation.md](../../docs/rules/documentation.md) - Documentation standards
- [cluster/flux/meta/priority-classes.yaml](../../cluster/flux/meta/priority-classes.yaml) - Priority class definitions

### Common YAML Schema URLs

Kubernetes resources (from kubernetes-schemas.pages.dev):

```yaml
# HelmRelease
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json

# Flux Kustomization
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json

# HelmRepository
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/source.toolkit.fluxcd.io/helmrepository_v1.json

# Kustomize kustomization.yaml
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
```

Helm values schemas (chart-specific, check if available):

```yaml
# bjw-s app-template (common library chart)
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/refs/tags/app-template-4.2.0/charts/library/common/values.schema.json

# external-dns
# yaml-language-server: $schema=https://raw.githubusercontent.com/kubernetes-sigs/external-dns/refs/heads/master/charts/external-dns/values.schema.json
```

**Note**: Not all charts provide schemas. Use `# #yaml-language-server: $schema=TODO` (double comment) when no schema is available - this marks it for future resolution while preventing IDE errors.
