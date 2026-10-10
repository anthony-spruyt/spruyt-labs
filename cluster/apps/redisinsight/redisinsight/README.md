# RedisInsight - Valkey Browser

## Overview

LAN-only UI for inspecting the cluster's Valkey instances, behind Authentik forward-auth (`RedisInsight Users` group). Connections are pre-seeded from a secret, so nothing is configured in the UI.

`app/config-eso.yaml` builds that secret (`redisinsight-config`): it pulls each instance's `redisinsight` password with ESO and templates `config.json`, which is loaded at startup via `RI_PRE_SETUP_DATABASES_PATH`. Nothing is in SOPS. Reloader restarts the pod when a password changes.

## Operations

### Connected instances

Each Valkey instance has a dedicated `redisinsight` ACL user. Permissions differ per instance:

| Instance         | Namespace       | ACL                  |
| ---------------- | --------------- | -------------------- |
| `valkey`         | `valkey-system` | read-only (`+@read`) |
| `litellm-valkey` | `litellm`       | full (`+@all`)       |

The full-access ACL on `litellm-valkey` means RedisInsight can delete keys there.

### Adding an instance

All four must change together:

1. A `redisinsight` user in the instance's `auth.aclUsers` and its password in that instance's users secret.
2. An `allow-redisinsight-ingress` CNP on the instance.
3. An egress CNP in `app/network-policies.yaml`.
4. A ServiceAccount, `SecretStore`, `data` entry and `config.json` entry in `app/config-eso.yaml`, plus a RoleBinding subject in the instance's `secret-reader-rbac.yaml`. Give the entry a new fixed UUID `id`: RedisInsight deletes pre-seeded connections whose `id` disappears.

For agent (MCP) access to a Valkey instance, see [db-mcp](../../db-mcp/db-mcp/README.md#adding-a-database).

### Service name

The Service is suffixed `-svc` on purpose. A Service named `redisinsight` makes Kubernetes inject `REDISINSIGHT_HOST`/`REDISINSIGHT_PORT`, which collide with the app's own env vars.

## References

- [RedisInsight](https://github.com/RedisInsight/RedisInsight)
