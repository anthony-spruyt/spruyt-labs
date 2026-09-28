# Cluster Bootstrap

One-time build of the cluster from bare metal: Talos on six nodes, then Cilium, then Flux, which deploys everything else from `cluster/`. For restoring data afterwards, continue with [disaster-recovery.md](disaster-recovery.md).

## Current Hardware

| Role          | Nodes                           | CPU                           | Memory | Disks                                  |
| ------------- | ------------------------------- | ----------------------------- | ------ | -------------------------------------- |
| Control plane | `e2-1`, `e2-2`, `e2-3`          | AMD Ryzen 5 3550H (4c/8t)     | 32 GB  | 512 GB NVMe (system)                   |
| Worker        | `ms-01-1`, `ms-01-2`, `ms-01-3` | Intel i5-12600H (hybrid, 16t) | 32 GB  | 512 GB NVMe (system), 1 TB NVMe (Ceph) |

Ceph OSDs run on the workers only. The workers are joined by a Thunderbolt ring that carries Ceph cluster traffic (see [rook-ceph-cluster/README.md](../cluster/apps/rook-ceph/rook-ceph-cluster/README.md)).

## Preconditions

- The devcontainer (or Coder workspace) from [DEVELOPMENT.md](../DEVELOPMENT.md). It ships `task`, `talosctl`, `topf`, `vals`, `sops`, `helmfile`, `kubectl`, `flux` and `terraform`.
- `SOPS_AGE_KEY_FILE` points at the Age key that decrypts `talos/*.sops.yaml` and `cluster/**/*.sops.yaml`.
- The Flux deploy key (`flux-gitops-key` private key) is available inside the container and its public half is a deploy key on the GitHub repository. The devcontainer does not mount it; copy it in for the bootstrap.
- Terraform Cloud access (`task terraform:login`) for the S3 buckets and Cloudflare tunnel.
- Console access to every node (keyboard and monitor, or BMC).

Do **not** run `task sops:decrypt` for this. It decrypts every SOPS file in the repo in place. `topf` decrypts `talenv.sops.yaml` and `talsecret.sops.yaml` in memory, and Flux decrypts cluster secrets in the cluster.

## 1. External Infrastructure (Terraform Cloud)

1. Log in and apply the workspace factory, which creates the other Terraform Cloud workspaces:

   ```bash
   task terraform:login
   cd infra/terraform/workspace-factory
   terraform init
   terraform plan
   terraform apply
   ```

2. The workspaces it creates (AWS buckets for Velero, CNPG and Ceph object storage, Cloudflare) are VCS-driven: runs queue in Terraform Cloud from pushes to `main`, not from the CLI. Variable sets and sensitive variables are described in [workspace-factory/README.md](../infra/terraform/workspace-factory/README.md).

**Verify:** every workspace shows a successful apply in the Terraform Cloud UI.

## 2. Talos

Node hostnames, roles and schematics are in [`talos/topf.yaml`](../talos/topf.yaml); addresses come from `talenv.sops.yaml`. Only edit them if hardware changed. Each node's install disk is selected by serial number in `talos/patches/node/<node-name>/01-configure-install-disk.yaml`, so **replacement hardware needs that serial updated** before anything is applied.

1. Generate the Talos client config from the secrets bundle:

   ```bash
   task talos:talosconfig
   ```

   **Verify:** `talosctl config info` shows the `spruyt-labs` context and a certificate expiry in the future.

2. Boot every node from the SecureBoot ISO for its hardware class. ISO links and schematic IDs are in the [schematics table](../talos/README.md#talos-image-schematics). On first install, enrol the Talos SecureBoot keys from the ISO boot menu.

   **Verify:** each node answers in maintenance mode on its configured address:

   ```bash
   talosctl -n <node-ip> get disks --insecure
   ```

3. Apply the config to all nodes and bootstrap etcd on the first control plane. `topf` prompts for confirmation and applies control-plane nodes one at a time:

   ```bash
   bash .taskfiles/talos/scripts/apply.sh --auto-bootstrap
   ```

   This path has not yet been exercised on this cluster (topf replaced talhelper after the last full build). If it fails, fall back to applying rendered configs node by node, then bootstrapping once:

   ```bash
   task talos:render
   talosctl apply-config --insecure -n <node-ip> --file talos/clusterconfig/topf/<node-name>.yaml
   talosctl bootstrap -n <first-control-plane-ip> -e <first-control-plane-ip>
   ```

   **Verify:** etcd has three members once all control planes have installed:

   ```bash
   talosctl -n <control-plane-ip> -e <control-plane-ip> etcd members
   ```

4. Fetch an admin kubeconfig. The devcontainer mounts `~/.secrets/kubeconfig` read-only, so write a new file and copy it to the host afterwards:

   ```bash
   talosctl kubeconfig -n <control-plane-ip> -e <control-plane-ip> --merge=false ~/kubeconfig-bootstrap
   export KUBECONFIG=~/kubeconfig-bootstrap
   ```

   **Verify:** `kubectl get nodes` lists all six nodes. They stay `NotReady` until Cilium is installed.

## 3. Cilium

Talos ships with no CNI or kube-proxy (`talos/patches/control-plane/17-*` and `18-*`), so Cilium must be installed before Flux can run.

1. In [`talos/helmfile/cilium-values.yaml`](../talos/helmfile/cilium-values.yaml), switch `k8sServiceHost` / `k8sServicePort` to the KubePrism pair (`localhost` / `7445`). The file carries both variants; the direct-address variant is only for recovering an already bootstrapped cluster.

2. Install Cilium:

   ```bash
   helmfile -f talos/helmfile/cilium.yaml apply --suppress-diff
   ```

3. Kubelets request serving certificates (`serverTLSBootstrap: true`), and `kubelet-csr-approver` is not running yet. Approve the pending requests:

   ```bash
   kubectl get csr -o name | xargs kubectl certificate approve
   ```

**Verify:** all nodes `Ready`, and Talos health passes:

```bash
kubectl get nodes
talosctl -n <control-plane-ip> -e <control-plane-ip> health
```

## 4. Flux

Flux is installed by the Flux Operator, not `flux bootstrap`. The `FluxInstance` values in [`flux-instance/app/values.yaml`](../cluster/apps/flux-system/flux-instance/app/values.yaml) point it at `./cluster/flux/cluster` using the `flux-gitops-key` secret, and SOPS decryption uses `sops-age`.

1. Create the namespace and the two secrets Flux needs before it can read the repo:

   ```bash
   kubectl create namespace flux-system
   kubectl -n flux-system create secret generic sops-age \
     --from-file=age.agekey="${SOPS_AGE_KEY_FILE}"
   ssh-keyscan github.com > /tmp/known_hosts
   kubectl -n flux-system create secret generic flux-gitops-key \
     --from-file=identity=<path-to-flux-gitops-key> \
     --from-file=known_hosts=/tmp/known_hosts
   ```

2. Install the operator and instance:

   ```bash
   helmfile -f talos/helmfile/flux.yaml apply --suppress-diff
   ```

**Verify:** the instance is ready and the two root Kustomizations reconcile. The full tree takes a while; re-run the second command until it prints nothing:

```bash
kubectl -n flux-system get fluxinstance flux
flux get kustomizations -A --status-selector ready=false
```

Flux then takes over the Cilium and Flux Operator Helm releases installed above (same release names) and upgrades them to the versions pinned in `cluster/apps/`.

If Kustomizations fail with `no matches for kind "Certificate"`, cert-manager's CRDs are not in place yet. Install the CRDs for the chart version pinned in `cluster/apps/cert-manager/cert-manager/app/release.yaml`:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/<version>/cert-manager.crds.yaml
```

## 5. Final Checks

| Check          | Command                                                           | Good                    |
| -------------- | ----------------------------------------------------------------- | ----------------------- |
| Nodes          | `kubectl get nodes`                                               | 6 `Ready`               |
| etcd           | `talosctl -n <cp-1-ip>,<cp-2-ip>,<cp-3-ip> etcd status`           | 3 members, no errors    |
| Flux           | `flux get kustomizations -A --status-selector ready=false`        | No rows                 |
| Ceph           | `kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status` | `HEALTH_OK`, 3 OSDs up  |
| Velero storage | `velero backup-location get`                                      | `aws-primary Available` |
| Talos drift    | `task talos:diff`                                                 | Exit code 0             |

Copy `~/kubeconfig-bootstrap` to `~/.secrets/kubeconfig` on the host so the next container rebuild picks it up. Then restore application data with [disaster-recovery.md](disaster-recovery.md).

## Related

- [talos/README.md](../talos/README.md) - patch layering, schematics, Talos tasks
- [cluster/flux/README.md](../cluster/flux/README.md) - Flux layout
- [infra/README.md](../infra/README.md) - Terraform workspaces
