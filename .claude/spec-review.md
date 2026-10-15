# Spec review checks (spruyt-labs)

Verify the spec's claims about existing infrastructure against the cluster:

- Read the deployed manifests in `cluster/apps/` for every component the spec references.
- Use `kubectl` for live state where manifests alone are insufficient.
- Check the namespace config the spec mentions: CNPs, RBAC, Kyverno policies, and network policies between the components that talk to each other.
- Cite the manifest you read for any finding that depends on what is deployed.
