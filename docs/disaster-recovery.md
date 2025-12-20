# Disaster Recovery Guide

Procedures for recovering the Talos Linux Kubernetes cluster from various failure scenarios.

## Backup Systems

### Velero (Kubernetes Resources)

Velero backs up Kubernetes resources and persistent volumes to S3.

```bash
# Check backup status
velero get backups
velero backup describe <backup-name>

# Check schedules
velero get schedules

# Check backup storage locations
kubectl get backupstoragelocations -n velero
```

### CNPG (PostgreSQL Databases)

CloudNativePG handles PostgreSQL backups via Barman to S3.

```bash
# Check cluster status
kubectl get clusters -A

# Check backup status
kubectl get backups -n <namespace>
```

### Ceph (Block/File Storage)

Ceph provides redundant storage with automatic replication.

```bash
# Check Ceph health
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd status
```

## Recovery Procedures

### Restore Kubernetes Resources (Velero)

1. **List available backups**:

   ```bash
   velero get backups
   ```

2. **Describe backup to verify contents**:

   ```bash
   velero backup describe <backup-name> --details
   ```

3. **Create restore**:

   ```bash
   # Full restore
   velero restore create <restore-name> --from-backup <backup-name>

   # Namespace-specific restore
   velero restore create <restore-name> --from-backup <backup-name> \
     --include-namespaces <namespace>

   # Exclude specific resources
   velero restore create <restore-name> --from-backup <backup-name> \
     --exclude-resources persistentvolumeclaims
   ```

4. **Monitor restore progress**:

   ```bash
   velero restore describe <restore-name>
   velero restore logs <restore-name>
   ```

### Restore PostgreSQL Database (CNPG)

1. **Check available backups**:

   ```bash
   kubectl get backups -n <namespace>
   ```

2. **Create recovery cluster from backup**:

   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Cluster
   metadata:
     name: <cluster-name>-restored
   spec:
     bootstrap:
       recovery:
         source: <cluster-name>
     externalClusters:
       - name: <cluster-name>
         barmanObjectStore:
           destinationPath: s3://<bucket>/<path>
           s3Credentials:
             accessKeyId:
               name: <secret-name>
               key: ACCESS_KEY_ID
             secretAccessKey:
               name: <secret-name>
               key: ACCESS_SECRET_KEY
   ```

### Node Replacement

1. **Cordon and drain the node**:

   ```bash
   kubectl cordon <node-name>
   kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
   ```

2. **Set Ceph noout flag** (if node has OSDs):

   ```bash
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd set noout
   ```

3. **Provision replacement node** with Talos ISO

4. **Apply Talos configuration**:

   ```bash
   talosctl apply-config --insecure --nodes <new-node-ip> \
     --file talos/clusterconfig/<node-hostname>.yaml
   ```

5. **Verify node joins cluster**:

   ```bash
   kubectl get nodes
   talosctl health
   ```

6. **Unset Ceph noout flag**:

   ```bash
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd unset noout
   ```

7. **Verify Ceph recovery**:

   ```bash
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
   ```

### Ceph Recovery

#### Single OSD Failure

Ceph handles single OSD failures automatically. Monitor recovery:

```bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd tree
```

#### Multiple OSD Failures

1. **Assess damage**:

   ```bash
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph health detail
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd tree
   ```

2. **If pool is degraded but recoverable**, wait for automatic recovery

3. **If OSDs are permanently lost**, remove them:

   ```bash
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd out <osd-id>
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd crush remove osd.<osd-id>
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph auth del osd.<osd-id>
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd rm <osd-id>
   ```

### Full Cluster Rebuild

In case of complete cluster loss:

1. **Follow bootstrap procedure** in [docs/bootstrap.md](bootstrap.md)

2. **Restore from Velero backup**:

   ```bash
   # After Flux is running and Velero is deployed
   velero restore create full-restore --from-backup <latest-backup>
   ```

3. **Restore databases from CNPG backups** as needed

4. **Verify all workloads**:

   ```bash
   kubectl get pods -A
   flux get kustomizations -A
   ```

## Validation

After any recovery:

- [ ] All nodes report Ready status: `kubectl get nodes`
- [ ] Flux kustomizations reconciled: `flux get ks -A`
- [ ] Core services running: Cilium, cert-manager, Traefik
- [ ] Ceph healthy: `ceph status` shows HEALTH_OK
- [ ] Applications accessible via ingress
- [ ] Monitoring dashboards show data

## Related

- [cluster/apps/velero/velero/README.md](../cluster/apps/velero/velero/README.md) - Velero details
- [cluster/apps/rook-ceph/README.md](../cluster/apps/rook-ceph/README.md) - Ceph details
- [docs/bootstrap.md](bootstrap.md) - Full cluster bootstrap
- [talos/README.md](../talos/README.md) - Talos node procedures
