# Temporal - Durable Workflow Engine

## Overview

Temporal runs long-lived, retryable workflows for the agent platform. It replaces n8n dispatch and BullMQ as the job engine (see `docs/agent-platform-v2.md`). Deployed with the official `temporalio/helm-charts` chart in the `temporal-system` namespace at `standard` priority. Four server services (frontend, history, matching, worker), the web UI, and an admin-tools pod, all backed by a CNPG
PostgreSQL cluster.

## Prerequisites

- CNPG operator deployed (dependency)
- External Secrets deployed (dependency)
- Barman Cloud plugin deployed (dependency), with the `temporal-secret-reader` Role and barman ingress entry in `cluster/apps/cnpg-system/plugin-barman-cloud/app/`
- Traefik deployed (dependency)
- Authentik deployed (dependency)

## Database

See [CNPG operator docs](../../cnpg-system/cnpg-operator/README.md#kubectl-cnpg-plugin) for `kubectl cnpg` plugin usage. Cluster name: `temporal-cnpg-cluster`.

Two databases on one cluster, both owned by the `temporal` role:

| Database              | Store      | Created by                        |
| --------------------- | ---------- | --------------------------------- |
| `temporal`            | default    | `bootstrap.initdb` on the Cluster |
| `temporal_visibility` | visibility | `Database` CRD                    |

The chart does not create databases (`createDatabase: false`). It only runs schema migrations, as a plain Job named `temporal-schema-<chart>-<revision>`, on every Helm revision. Connections use TLS with host verification against the CNPG CA mounted from `temporal-cnpg-cluster-ca`.

## Operations

### Connecting a client

In-cluster address: `temporal-frontend.temporal-system.svc:7233` (gRPC). Clients need a Cilium egress rule to that port and a matching ingress rule added to `allow-temporal-frontend-clients-ingress` in `app/network-policies.yaml`.

### Namespaces

Temporal namespaces are declared under `server.config.namespaces.namespace` in `app/values.yaml`. A Job creates any that are missing on each Helm revision. Only `default` (3 day retention) exists today.

### Admin CLI

```bash
kubectl exec -n temporal-system deploy/temporal-admintools -- temporal operator namespace list
```

### UI access

`https://temporal.lan.${EXTERNAL_DOMAIN}` behind Authentik forward-auth and the LAN whitelist. Users must be in the `Temporal Users` group in Authentik. The UI is admin-only, so it stays LAN-scoped.

### External webhooks

Temporal has no webhook receiver. GitHub and other external callers hit an intake service (n8n today) that verifies the payload and starts a workflow over the in-cluster gRPC address above, or the HTTP API on `temporal-frontend:7243`. Do not expose the frontend ports publicly; they have no authentication by default.

## Troubleshooting

1. **History shard count cannot be changed**

   - **Symptom**: History pods crash-loop after editing `numHistoryShards` with a shard count mismatch error.
   - **Resolution**: Revert the value. It is fixed at first schema setup. Changing it means dropping both databases and starting over.

2. **Schema Job fails with TLS or auth errors**

   - **Symptom**: `manage-schema-*` init containers restart repeatedly.
   - **Resolution**: Check that `temporal-cnpg-cluster-app` and `temporal-cnpg-cluster-ca` exist and that the CNPG cluster is Ready. The Job retries on its own once the database is up.

3. **Web UI returns 502 from Traefik**

   - **Symptom**: Login works but the page shows a gateway error.
   - **Resolution**: The UI pod only starts once it can reach the frontend service. Check `temporal-frontend` pod readiness first.

## References

- [Temporal Helm chart](https://github.com/temporalio/helm-charts)
- [Temporal self-hosted guide](https://docs.temporal.io/self-hosted-guide)
- [Temporal configuration reference](https://docs.temporal.io/references/configuration)
- [CloudNative-PG Documentation](https://cloudnative-pg.io/)
