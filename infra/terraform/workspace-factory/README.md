# Bootstrap a new Terraform Cloud Workspace

> Bootstraps new workspaces backed by workload identities.

Bootstrapping a workspace does require a token but it can be disabled/deleted afterwards or a time limited token can be used.

## Workspaces

The following workspaces are created by this workspace factory.

### ceph-objectstore

A AWS Rook Ceph S3 object store for the spruyt labs cluster.

Make sure to activate the access key before any changes and to deactivate it after usage [here](https://us-east-1.console.aws.amazon.com/iam/home?region=ap-southeast-4#/users/details/tfc-admin?section=security_credentials).
