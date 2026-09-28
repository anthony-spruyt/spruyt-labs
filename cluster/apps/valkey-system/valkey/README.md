# Valkey - Shared Queue Store

## Overview

Shared Valkey instance backing the n8n BullMQ queue, with read access for RedisInsight. `agent-worker-system` and `litellm` run their own separate Valkey releases; they do not use this one.

## Operations

### Users and credentials

Each consumer gets its own ACL user (`aclUsers` in `app/values.yaml`); the password for each user is the key of the same name in `app/valkey-secrets.sops.yaml`. The `default` user is locked out (`-@all`).

Consumers in other namespaces pull their password with ESO rather than a SOPS copy: a `SecretStore` with `remoteNamespace: valkey-system` plus an `ExternalSecret` reading the user's key from `valkey-secrets`. The Role in `app/secret-reader-rbac.yaml` grants that read per consumer ServiceAccount. `n8n/app/valkey-secret-store.yaml` and `valkey-external-secret.yaml` are the template. n8n's ACL only
covers `n8n:*`, which matches its `QUEUE_BULL_PREFIX`.

Adding a consumer: add an ACL user, a key in `valkey-secrets`, a Role/RoleBinding here, and an ingress rule in `app/network-policies.yaml`.

### Exporter password workaround

The chart hard-wires the exporter's `REDIS_PASSWORD` to the `default` user's key, and strategic merge dedupes env vars by name, so `extraEnvs` cannot override it. A `postRenderers` patch in `app/release.yaml` repoints it at the `metrics` key. Keep it until the chart lets the exporter credential be chosen.

`maxmemory-policy noeviction` is deliberate: evicting BullMQ keys silently loses jobs, so a full instance should fail writes loudly instead.
