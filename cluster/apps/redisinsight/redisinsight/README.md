# RedisInsight - Valkey Browser

## Overview

LAN-only UI for inspecting the cluster's Valkey instances, behind Authentik forward-auth (`RedisInsight Users` group). Connections are pre-seeded from a secret, so nothing is configured in the UI.

## Operations

### Connected instances

Each Valkey instance has a dedicated `redisinsight` ACL user. Permissions differ per instance:

| Instance         | Namespace             | ACL                  |
| ---------------- | --------------------- | -------------------- |
| `valkey`         | `valkey-system`       | read-only (`+@read`) |
| `agent-valkey`   | `agent-worker-system` | full (`+@all`)       |
| `litellm-valkey` | `litellm`             | full (`+@all`)       |

The full-access ACLs on `agent-valkey` and `litellm-valkey` mean RedisInsight can delete keys there, e.g. corrupted BullMQ jobs (see the [agent-queue-worker README](../../agent-worker-system/agent-queue-worker/README.md#troubleshooting)).

### Adding an instance

All four must change together:

1. A `redisinsight` user in the instance's `auth.aclUsers` and its password in that instance's users secret.
2. An `allow-redisinsight-ingress` CNP on the instance.
3. An egress CNP in `app/network-policies.yaml`.
4. A connection entry in `config.json` inside `app/redisinsight-secrets.sops.yaml`, loaded at startup via `RI_PRE_SETUP_DATABASES_PATH`.

For agent (MCP) access to a Valkey instance, see [db-mcp](../../db-mcp/db-mcp/README.md#adding-a-database).

### Service name

The Service is suffixed `-svc` on purpose. A Service named `redisinsight` makes Kubernetes inject `REDISINSIGHT_HOST`/`REDISINSIGHT_PORT`, which collide with the app's own env vars.

## References

- [RedisInsight](https://github.com/RedisInsight/RedisInsight)
