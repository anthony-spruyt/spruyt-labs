# Victoria Metrics Secret Writer - etcd TLS Certificate Provisioner

## Overview

One-shot Kubernetes Job that copies etcd TLS certificates from the host filesystem into a Kubernetes secret (`etcd-secrets`) in the `observability` namespace. This enables VictoriaMetrics to scrape etcd metrics over TLS.

**Priority**: standard

> **Note**: This is a Job (not a Deployment). It runs once, copies the certs, and exits. To re-run, delete the completed Job and reconcile.

## Prerequisites

- Kubernetes cluster with Flux CD
- Control plane nodes with etcd TLS certificates at `/system/secrets/etcd/`

## Architecture

The Job:

1. Schedules on a control plane node (nodeAffinity + toleration)
2. Mounts `/system/secrets/etcd` via hostPath
3. Uses `bitnami/kubectl` to create/update the `etcd-secrets` secret from `ca.crt`, `server.crt`, and `server.key`
4. Runs as the `secrets-writer` ServiceAccount with a Role scoped to secrets CRUD in the `observability` namespace

## Operation

### Key Commands

```bash
# Check Job status
kubectl get jobs -n observability etcd-secret-writer

# Check if the secret was created
kubectl get secret -n observability etcd-secrets

# Force re-run (delete completed Job, then reconcile)
kubectl delete job -n observability etcd-secret-writer
flux reconcile kustomization victoria-metrics-secret-writer --with-source

# View Job logs
kubectl logs -n observability -l job-name=etcd-secret-writer
```

## Troubleshooting

### Common Issues

1. **Job stuck in Pending**
   - **Symptom**: Pod not scheduled
   - **Resolution**: Verify control plane node has the `node-role.kubernetes.io/control-plane` label and the toleration is correct

2. **Job fails with permission denied**
   - **Symptom**: Pod logs show RBAC or filesystem errors
   - **Resolution**: Check `secrets-writer` ServiceAccount, Role, and RoleBinding exist in `observability` namespace. Verify etcd certs are readable at `/system/secrets/etcd/` on control plane nodes.

3. **Secret not updated after cert rotation**
   - **Symptom**: `etcd-secrets` contains stale certificates
   - **Resolution**: Delete the completed Job and reconcile to re-run it

## References

- [VictoriaMetrics etcd Monitoring](https://docs.victoriametrics.com/)
- [Kubernetes Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
