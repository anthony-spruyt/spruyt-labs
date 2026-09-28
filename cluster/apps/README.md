# Cluster Applications

Everything Flux deploys to the cluster lives here, one directory per namespace and one subdirectory per app. The `cluster-apps` Kustomization in [`cluster/flux/cluster/ks.yaml`](../flux/cluster/ks.yaml) reconciles this tree after `cluster-meta`.

Component READMEs are optional. Write one only when there is something the manifests can't tell you: a workaround, a manual or one-time step, an external prerequisite, cross-component wiring, or a credential to rotate. Never restate what `ks.yaml`, `release.yaml` or `values.yaml` already say.

- [Documentation standards](../../.claude/rules/05-documentation.md)
- [App layout and manifest patterns](../../.claude/rules/07-patterns.md)
- [Component README template](../../docs/templates/readme_template.md)
