# Spec review checks (spruyt-labs)

Verify the spec's claims about existing infrastructure against the cluster:

- Read the deployed manifests in `cluster/apps/` for every component the spec references.
- Use `kubectl` for live state where manifests alone are insufficient.
- Check the namespace config the spec mentions: CNPs, RBAC, Kyverno policies, and network policies between the components that talk to each other.
- Review the Kubernetes deployment: resource sizing, pod lifecycle, namespace/CNP/RBAC alignment with existing cluster config.
- Cite the manifest you read for any finding that depends on what is deployed.
