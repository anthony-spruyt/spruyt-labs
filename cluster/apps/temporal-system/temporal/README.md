# Temporal - Durable Workflow Engine

## Overview

Durable, retryable workflow engine intended to take over job orchestration for the agent platform from n8n dispatch and BullMQ (#3045). Deployed from the official Temporal chart against its own CNPG cluster. No workloads use it yet.

## Prerequisites

- `temporal-secret-reader` Role and a barman plugin ingress entry for `temporal-system` in `cluster/apps/cnpg-system/plugin-barman-cloud/app/`, outside this directory.

## Operations

### Database layout

Two databases on one CNPG cluster, both owned by the `temporal` role:

| Database              | Store      | Created by                        |
| --------------------- | ---------- | --------------------------------- |
| `temporal`            | default    | `bootstrap.initdb` on the Cluster |
| `temporal_visibility` | visibility | `Database` CRD                    |

The chart does not create databases (`createDatabase: false`). Helm hooks do not run under Flux, so schema migrations and namespace creation run as plain Jobs on every Helm revision. Connections use TLS with host verification against the CNPG CA (the `-rw` service name is in the operator-issued cert SANs).

`max_connections` is raised to 200 on the cluster because four server pods × two stores × `maxConns` 10 already consume 80 of the default 100. Recalculate if you add replicas or raise `maxConns`.

### Credentials

Both Postgres logins are ESO-generated (`sl_` prefix) in `app/cnpg-roles-eso.yaml`; nothing is in SOPS.

| Role       | Secret                | Used by                                           |
| ---------- | --------------------- | ------------------------------------------------- |
| `temporal` | `temporal-cnpg-owner` | Temporal server and schema Job (`existingSecret`) |
| `mcp`      | `temporal-cnpg-mcp`   | db-mcp, read-only (`pg_read_all_data`)            |

`bootstrap.initdb.secret` points CNPG at `temporal-cnpg-owner`, so CNPG no longer generates `temporal-cnpg-cluster-app`. Superuser access is off.

To rotate a login, delete both its Secret and its ExternalSecret (`kubectl -n temporal-system delete secret,externalsecret temporal-cnpg-owner`). Flux recreates the ExternalSecret, which generates a new password; CNPG applies it to the role. Then restart the server pods yourself (`kubectl -n temporal-system rollout restart deploy -l app.kubernetes.io/instance=temporal`) - Reloader ignores a
recreated Secret, so without this the pods keep the old password (brief outage).

### Connecting a client

In-cluster: `temporal-frontend.temporal-system.svc:7233` (gRPC) or `:7243` (HTTP API). Access is limited to listed clients by `allow-temporal-frontend-clients-ingress` in `app/network-policies.yaml`. A new client needs its own egress rule to 7233 and an entry there. Never expose the frontend through Traefik or the tunnel.

### Namespaces

Temporal namespaces are declared under `server.config.namespaces.namespace` in `app/values.yaml` and created on the next Helm revision. Only `default` (3-day retention) exists.

### External webhooks

Temporal has no webhook receiver. External callers (GitHub etc.) hit an intake service (n8n today) that verifies the payload and starts a workflow over gRPC.

### UI access

`https://temporal.lan.${EXTERNAL_DOMAIN}`, behind Authentik forward-auth and the LAN whitelist. Access requires the `Temporal Users` group. The UI is admin-only, so it stays LAN-scoped.

## Troubleshooting

1. **History pods crash-loop with a shard count mismatch after editing `numHistoryShards`**

   - **Cause**: The shard count is fixed at first schema setup.
   - **Fix**: Revert the value. Changing it means dropping both databases and starting over.

2. **Schema Job init containers restart repeatedly with TLS or auth errors**

   - **Fix**: Check `temporal-cnpg-owner` and `temporal-cnpg-cluster-ca` exist and the CNPG cluster is Ready. The Job retries on its own once the database is up.

3. **`CiliumPolicyDrops` for `temporal-system` after a node drain or Talos upgrade**

   - **Symptom**: Steady egress `POLICY_DENIED` drops from the server pods to IPs with no pod behind them, on membership ports 6933-6939.

   - **Cause**: Ringpop keeps dead peers as faulty for 24h (hardcoded in Temporal) and keeps dialing them. Not a missing CNP rule; do not add a `world` egress rule.

   - **Fix**: A rolling restart is not enough; a new pod rejoins through a survivor and inherits the stale list. Take all four servers down together (brief outage):

     ```bash
     kubectl -n temporal-system scale deploy/temporal-{frontend,history,matching,worker} --replicas=0
     # wait for the pods to terminate
     kubectl -n temporal-system scale deploy/temporal-{frontend,history,matching,worker} --replicas=1
     ```

## References

- [Temporal Helm chart](https://github.com/temporalio/helm-charts)
- [Temporal self-hosted guide](https://docs.temporal.io/self-hosted-guide)
- [Temporal configuration reference](https://docs.temporal.io/references/configuration)
