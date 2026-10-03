# plugin-barman-cloud - CNPG S3 Backups

## Overview

Barman Cloud plugin that ships WAL and base backups for every CNPG cluster to a single S3 bucket. This namespace also holds the one copy of the AWS credentials that every backing-up app pulls from.

## Prerequisites

- S3 bucket and IAM user from [`infra/terraform/aws/cnpg-backup/`](../../../../infra/terraform/aws/cnpg-backup/README.md). The access key from the Terraform outputs is copied by hand into `app/aws-secrets.sops.yaml` (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).

## Operations

### Adding backups for a new CNPG cluster

Four pieces, across two namespaces:

1. **Credentials** - in the app, a `ServiceAccount` `aws-secret-reader`, a `SecretStore` using the `kubernetes` provider with `remoteNamespace: cnpg-system`, and an `ExternalSecret` that copies `aws-secrets` into a secret the `ObjectStore` references. Copy `temporal/app/aws-secret-store.yaml` and `aws-barman-eso.yaml`.
2. **Read access** - add a Role/RoleBinding pair to `app/secret-reader-rbac.yaml` here, scoped by `resourceNames` to `aws-secrets` and bound to the app's `aws-secret-reader` ServiceAccount.
3. **ObjectStore + plugin** - an `ObjectStore` in the app, referenced from the `Cluster` under `plugins: [{name: barman-cloud.cloudnative-pg.io, parameters.barmanObjectName: ...}]`.
4. **Network** - add an ingress rule on port 9090 for the new cluster's pods to `app/network-policies.yaml` here, and a matching egress CNP in the app namespace.

Sync the credentials into a **dedicated** secret rather than merging them into the app's main secret. Several charts `envFrom` their main secret into every pod, which would leak the AWS keys as environment variables (the reason `temporal` uses a separate `*-cnpg-aws-secrets`).

### Rotating the AWS key

Update `app/aws-secrets.sops.yaml`. Every consumer ExternalSecret picks up the new key on its own `refreshInterval`; there is no per-app copy to edit.

## References

- [Barman Cloud plugin](https://cloudnative-pg.io/plugin-barman-cloud/)
