# kubernetes.md

Kubectl workflow guidelines for Spruyt-labs homelab engineers working with Kubernetes custom resources, Helm charts, and cluster-level specifications. Use this reference before making configuration changes.

## Quick-start verification checklist

- [ ] Confirm that the target resource type exists by running `kubectl api-resources` and recording the group/version you will touch.
- [ ] Review every field you intend to modify with `kubectl explain <resource_type>[.<field_path>]`, expanding child fields with `--recursive` when necessary.
- [ ] Retrieve and archive the current manifest with `kubectl get <resource_type> <resource_name> -n <namespace> -o yaml`, highlighting controller-managed sections you must not overwrite.
- [ ] Validate Helm chart defaults or CRD documentation through approved Context7 libraries or trusted upstream references, citing the material in your change notes.
- [ ] Capture assumptions, dependencies, and upstream version requirements so reviewers can confirm that automation and Talos state will reconcile cleanly.

> Complete every step before submitting a pull request or applying a live change. Skipping verification increases the risk of Flux/Talos drift and unexpected reconciliations.

## Why these steps matter

Verifying the API surface, specification, and live configuration keeps Talos-managed clusters consistent with Flux automation and prevents overwriting controller-managed fields. Reviewing upstream documentation surfaces breaking changes before they impact production workloads and provides reviewers with traceable evidence.

## Command reference

### List available resource types and API groups

```sh
kubectl api-resources
```

### Explain resource specification fields

```sh
kubectl explain <resource_type>[.<field_path>]
```

Use `--recursive` when you need to inspect nested fields.

### Retrieve the live manifest for inspection

```sh
kubectl get <resource_type> <resource_name> -n <namespace> -o yaml
```

### Validate chart or manifest documentation

Use approved Context7 libraries, cluster documentation, or vendor references to confirm values and defaults. Document the sources you review so reviewers can validate the same information.
