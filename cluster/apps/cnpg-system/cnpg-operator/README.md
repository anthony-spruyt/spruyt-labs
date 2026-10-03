# CloudNativePG Operator - PostgreSQL Management

## Overview

Cluster-wide operator for every app database (authentik, n8n, coder, temporal, litellm). Backups go through the Barman Cloud plugin; see [plugin-barman-cloud](../plugin-barman-cloud/README.md) for the S3 wiring.

## kubectl cnpg Plugin

Install with `task install:cnpg-plugin`. Operations worth knowing:

```bash
# Detailed status, including replication and WAL archiving health
kubectl cnpg status <cluster-name> -n <namespace>

# Rolling restart - preferred over deleting pods after a secret rotation or config change
kubectl cnpg restart <cluster-name> -n <namespace>

# Reload configuration without a restart
kubectl cnpg reload <cluster-name> -n <namespace>

# On-demand backup
kubectl cnpg backup <cluster-name> -n <namespace>
```

## Operations

A cluster hibernated with the `cnpg.io/hibernation: "on"` annotation never reports Ready, so its Flux Kustomization needs `wait: false` while hibernated.

## References

- [CloudNativePG documentation](https://cloudnative-pg.io/documentation/current/)
- [kubectl cnpg plugin](https://cloudnative-pg.io/documentation/current/kubectl-plugin/)
