# Valkey - Shared Queue Store

## Overview

Shared Valkey instance backing the n8n BullMQ queue, with read access for RedisInsight. `litellm` runs its own separate Valkey release; it does not use this one.

## Operations

### Users and credentials

Each consumer gets its own ACL user (`aclUsers` in `app/values.yaml`). The password for each user is the key of the same name in the `valkey-users` secret, which only ESO writes: `app/users-eso.yaml` has one `Password` generator and one `CreatedOnce` ExternalSecret per user, adding the `sl_` prefix. Nothing is in SOPS.
The `default` user can only run `PING` (`-@all +ping`), which the chart's health probes use.

Consumers in other namespaces pull their password with ESO: a `SecretStore` with `remoteNamespace: valkey-system` plus an `ExternalSecret` reading the user's key from `valkey-users`. `app/secret-reader-rbac.yaml` grants that read per consumer ServiceAccount. `n8n/app/valkey-secret-store.yaml` and `externalsecret-valkey.yaml` are the template. n8n's ACL only covers `n8n:*`, which matches its
`QUEUE_BULL_PREFIX`.

Adding a consumer: add an ACL user and its ExternalSecret in `app/users-eso.yaml`, a subject in `app/secret-reader-rbac.yaml`, and an ingress rule in `app/network-policies.yaml`. Land the ExternalSecret in an earlier push than the `aclUsers` entry: the chart's init script exits if any user has no key.

Rotating a user: delete its ExternalSecret (`kubectl delete externalsecret -n valkey-system valkey-user-<user>`). Flux recreates it, which writes a new password; Reloader restarts Valkey, and consumers restart when their synced copy changes (within 5 minutes). Never delete the `valkey-users` secret itself - every user would get a new password at once.

### Memory

`maxmemory-policy noeviction` is deliberate: evicting BullMQ keys silently loses jobs, so a full instance should fail writes loudly instead.
