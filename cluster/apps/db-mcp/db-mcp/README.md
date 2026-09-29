# db-mcp - Read-only Database MCP Servers

## Overview

One pod that gives agents read-only SQL and Valkey access through the LiteLLM MCP gateway, so debugging a database needs no `kubectl exec` and no credential handling. DBHub serves every Postgres source from one process; the Redis MCP server binds to a single server, so each Valkey instance gets its own container.

LiteLLM's built-in catalog entries for Postgres and Redis are not usable: the LiteLLM image has no `npx`, `@modelcontextprotocol/server-postgres` is deprecated and `@anthropic/mcp-server-redis` does not exist on npm.

## Operations

### Endpoints

| LiteLLM server | URL                                 | Backs                                              |
| -------------- | ----------------------------------- | -------------------------------------------------- |
| `postgres`     | `http://db-mcp.db-mcp.svc:8080/mcp` | Postgres: `n8n`, `temporal`, `temporal_visibility` |
| `valkey-agent` | `http://db-mcp.db-mcp.svc:8001/mcp` | Valkey: `agent-valkey`                             |
| `valkeyshared` | `http://db-mcp.db-mcp.svc:8002/mcp` | Valkey: `valkey-system/valkey`                     |

With more than one source, DBHub suffixes each tool with the source id (`execute_sql_n8n`, `search_objects_temporal`); enable new ones in the LiteLLM allowlist when a source is added.

Registration is manual in the LiteLLM UI, like every MCP server behind LiteLLM - see [litellm README](../../litellm/README.md#mcp-servers). Restrict each server to its read tools with LiteLLM's tool allowlist.

### Security model

Neither server authenticates callers. The boundary is three layers:

1. `allow-litellm-ingress` CNP - only LiteLLM reaches the pod.
2. A read-only database login per source (below) - writes fail at the database.
3. The LiteLLM tool allowlist per server.

DBHub's `readonly = true` is defence in depth only; it cannot stop a privileged role, which is why the role itself must be read-only.

Read-only still means readable: whatever a source holds can land in an agent's context and the LLM provider's logs. Databases that store credentials (`coder`: OAuth and agent tokens; `authentik`: sessions and provider secrets) are deliberately not sources. `pg_read_all_data` cannot exclude tables.

### Credentials - one copy per password

Each database owns its `mcp` password; nothing is stored in SOPS for this app.

| Source                             | Login                                                 | Generated into (owner ns)               | Synced to `db-mcp`    |
| ---------------------------------- | ----------------------------------------------------- | --------------------------------------- | --------------------- |
| n8n Postgres                       | CNPG managed role `mcp`, member of `pg_read_all_data` | `n8n-cnpg-mcp` (`n8n-system`)           | `db-mcp-n8n`          |
| temporal Postgres (both databases) | CNPG managed role `mcp`, member of `pg_read_all_data` | `temporal-cnpg-mcp` (`temporal-system`) | `db-mcp-temporal`     |
| agent-valkey                       | ACL user `mcp`, `+@read` only                         | `mcp` key in `agent-valkey-users`       | `db-mcp-agent-valkey` |
| valkey                             | ACL user `mcp`, `+@read` only                         | `mcp` key in `valkey-users`             | `db-mcp-valkey`       |

Passwords come from an ESO `Password` generator with `refreshPolicy: CreatedOnce`, so they are generated once and not refreshed on a timer. The template adds the `sl_` prefix (64 alphanumerics after it), so the LiteLLM secret-masking middleware recognises them as ours.

To rotate:

- **Postgres**: delete both the `<cluster>-mcp` Secret and ExternalSecret (they share a name); Flux recreates the ExternalSecret, which generates a new password, and CNPG applies it to the role.
- **Valkey**: delete the `<instance>-user-mcp` ExternalSecret; Flux recreates it and a new `mcp` key is written.

Valkey only reads passwords at startup, so each Valkey has Reloader auto mode on and restarts when its users secret changes. `db-mcp` restarts on its side too, when its synced copy changes (within 5 minutes).

### Adding a database

Postgres (same pattern as n8n):

1. In the owning app: `Password` generator + `ExternalSecret` (basic-auth, `cnpg.io/reload` label), a `managed.roles` entry `mcp` in `pg_read_all_data`, a Role/RoleBinding letting `db-mcp`'s reader ServiceAccount read that one secret, and a CNP allowing ingress from `db-mcp`.
2. Here: ServiceAccount + `SecretStore` + `ExternalSecret` in `secret-stores.yaml`, an egress CNP, a `[[sources]]` + `[[tools]]` block in `dbhub.toml` and the password env var on the `dbhub` container.
3. In LiteLLM, enable the new source's `execute_sql_<id>` and `search_objects_<id>` tools on the `postgres` server.

Valkey (same pattern as agent-valkey):

1. In the Valkey app: an `<instance>-user-mcp` ExternalSecret in `users-eso.yaml`, an `mcp` user in `auth.aclUsers` (in a later push than the ExternalSecret), a RoleBinding subject in `secret-reader-rbac.yaml` and a CNP allowing ingress from `db-mcp`.
2. Here: SecretStore + ExternalSecret, egress CNP, a new `redis-<instance>` container on the next port, the port on the Service and on both LiteLLM CNPs.
3. Register the new port as its own MCP server in LiteLLM.

## Troubleshooting

1. **Valkey pod stuck in init after adding the `mcp` user**

   - **Cause**: the chart's init script exits when any `aclUsers` entry has no password key, and ESO had not written the `mcp` key yet.
   - **Fix**: check the `<instance>-user-mcp` ExternalSecret is `Ready`; the pod recovers on its own once the key exists. Land the ExternalSecret in a push before the `aclUsers` entry to avoid the window entirely.

2. **DBHub 403 "Host ... is not allowed" / Redis MCP 421**

   - **Cause**: LiteLLM called the pod by a hostname not in `--allowed-hosts` / `MCP_ALLOWED_HOSTS`.
   - **Fix**: register the server with the exact `db-mcp.db-mcp.svc` host shown above.

3. **`password authentication failed for user "mcp"`**

   - **Cause**: CNPG had not applied the role password yet, or the generated secret was recreated after the role was set.
   - **Fix**: check the Cluster's managed roles status with `kubectl cnpg status n8n-cnpg-cluster -n n8n-system`.

## References

- [DBHub](https://github.com/bytebase/dbhub)
- [Redis MCP Server](https://github.com/redis/mcp-redis)
- [CNPG declarative role management](https://cloudnative-pg.io/documentation/current/declarative_role_management/)
- [ESO Password generator](https://external-secrets.io/latest/api/generator/password/)
