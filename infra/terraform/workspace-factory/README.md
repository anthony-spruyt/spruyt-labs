# Bootstrap a new Terraform Cloud Workspace

> Bootstraps new workspaces backed by workload identities.

Bootstrapping does require a token but it can be removed afterwards or a time limited token can be used.
Whenever a new workspace is bootstrapped a new token will need to be configured in the Terraform cloud portal.

## Workspaces

The following workspaces are created by this workspace factory.

- `ceph-objectstore` which is a AWS Rook Ceph S3 object store for the spruyt labs cluster.
