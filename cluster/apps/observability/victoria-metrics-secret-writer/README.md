# victoria-metrics-secret-writer - etcd Client Certificate Copy

## Overview

One-shot Job that copies the etcd CA and server certificate/key from a control-plane node's `/system/secrets/etcd/` into the `etcd-secrets` Secret, which the k8s-stack etcd scrape uses for mTLS. Talos exposes no other way to get etcd client credentials into the cluster.

## Operations

- **Re-running**: the Kustomization sets `force: true`, so changing the Job spec in Git makes Flux delete and recreate it. Without a spec change, delete the completed Job and let Flux recreate it.
- **After etcd certificate rotation** (Talos upgrades or a CA rotation) the copied certs go stale and etcd scrapes fail with TLS errors. Re-run the Job.
- **`runAsUser: 60`** matches the owner of the etcd PKI files on Talos; any other UID cannot read the key.
- `etcd-secrets` holds the etcd server key; keep read access limited to the etcd scrape.
