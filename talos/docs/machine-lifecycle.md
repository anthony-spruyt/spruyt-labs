<!-- markdownlint-disable MD013 -->

# Talos Machine Lifecycle Deep Dive

## Summary and Ownership

Talos lifecycle operations for spruyt-labs are owned by the platform engineering team. This deep dive extends the operational runbook in [talos/README.md](../README.md) with detailed procedures required to provision, update, and recover Talos-managed machines across baremetal and virtual pools. Use this document when executing day-0 installs, GitOps-driven machineconfig changes, or incident response that touches Talos nodes.

## Preconditions

- Work from the project devcontainer or install `talhelper`, `talosctl`, `kubectl`, `flux`, `task`, `age`, and `sops` locally.
- Confirm you have access to the Age identity capable of decrypting Talos secrets (`talos/talenv.sops.yaml`, `talos/talsecret.sops.yaml`).
- Sync the latest `main` branch and start from a clean feature branch before changing machine definitions.
- Validate Flux controllers prior to disruptive work:

```bash
flux get kustomizations -n flux-system
```

- Ensure out-of-band management or console access for each physical node to recover from Talos API loss.
- Maintain an accurate hardware inventory (serial numbers, rack position, VLAN assignments) in the shared asset tracker.

## Provisioning New Hardware or VMs

### Configuration Preparation

1. Update [`talos/talconfig.yaml`](../talconfig.yaml) with new node metadata (hostname, IP, schematic reference, disk layout).
2. Create or extend overlay snippets in `cluster/machines/*` (control-plane, workers, VMs) to declare node-specific patches.
3. Regenerate rendered configs:

```bash
talhelper genconfig
```

Outputs are written to `talos/clusterconfig/` (gitignored) for secure distribution.

4. If secrets need rotation or first-time generation, run:

```bash
task talos:gen
```

### Physical Hardware Provisioning

1. Download the SecureBoot ISO matching the hardware class (see [Talos image schematics](#talos-image-schematics)).
2. Boot from USB/PXE, select the encrypted target disk, and wait for the Talos API to advertise readiness:

```bash
talosctl health --nodes <node-ip>
```

3. Apply the rendered configuration:

```bash
talosctl apply-config --insecure --nodes <node-ip> \
   --file talos/clusterconfig/<hostname>.yaml
```

4. For the first control-plane node, perform bootstrap:

```bash
talosctl bootstrap --nodes <control-plane-ip>
```

Record the etcd snapshot generated during the bootstrap sequence.

### Virtual Machine Provisioning

1. Provision a UEFI VM with at least 2 vCPUs and attach the SecureBoot ISO.
2. Place the VM NIC on the appropriate VLAN and assign the IP declared in `talconfig`.
3. Inject the rendered `machineconfig` via virtual media or cloud-init userdata.
4. Apply the configuration with `talosctl apply-config` once the Talos API is reachable.
5. Verify kubelet registration:

```bash
kubectl get nodes -o wide | grep <hostname>
```

### Documentation

Update the machine inventory sheet with hardware IDs, BMC credentials, and schematic references after provisioning completes.

## GitOps Update Flow

1. Start a feature branch: `git checkout -b feat/talos-<change>`.
2. Edit the relevant overlays and Talos patch snippets (`talos/patches/`).
3. Render configs and review diffs without writing secrets:

```bash
talhelper genconfig --dry-run --diff
```

4. Execute repository checks:

```bash
task validate
task dev-env:lint
```

5. Commit changes referencing affected lifecycle phases (Plan, Apply, Validate) and open a PR.
6. After merge, prompt reconciliation:

```bash
flux reconcile kustomization cluster-machines --with-source
```

7. Confirm nodes consume the new configuration:

```bash
talosctl -n <node-ip> get machineconfig -o yaml
```

For persistent drift, reapply configs:

```bash
talosctl apply-config --nodes <node-ip> \
   --file talos/clusterconfig/<hostname>.yaml
```

## Node Pool Management

### Control Plane

- Maintain an odd number of control-plane nodes for etcd quorum.
- Enforce taints and labels declaratively; reconcile outstanding drift with:

```bash
kubectl label node <hostname> node-role.kubernetes.io/control-plane=
kubectl taint node <hostname> node-role.kubernetes.io/control-plane=:NoSchedule
```

- Monitor etcd health during planned changes:

```bash
talosctl -n <node-ip> etcd health
```

### Worker Pools

- Group workers by hardware class or topology with labels such as:

```bash
kubectl label node <hostname> topology.spruyt-labs.io/rack=r01
kubectl label node <hostname> node.kubernetes.io/instance-type=ms-01
```

- Apply workload taints in overlays to prevent manual configuration drift.
- For burst capacity, stage VM overlays and destroy them cleanly by removing the overlay and re-running Flux reconciliation.

## Maintenance

### Planned Maintenance

1. Cordon and drain workloads:

```bash
kubectl cordon <hostname>
kubectl drain <hostname> --ignore-daemonsets --delete-emptydir-data
```

2. Perform hardware service or firmware upgrades.
3. Return the node to service:

```bash
kubectl uncordon <hostname>
```

### Talos OS Upgrades

1. Review available factory images in [Talos image schematics](#talos-image-schematics).
2. Execute the upgrade:

```bash
talosctl upgrade --nodes <node-ip> \
   --image factory.talos.dev/metal-installer-secureboot/<schematic>:<version>
```

3. Validate versions:

```bash
talosctl version -n <node-ip>
```

4. Reapply machine configs if needed to eliminate drift.

### Graceful Shutdown and Restart

1. Set Ceph flags to prevent rebalance (run inside the rook-ceph toolbox):

```bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- bash
```

```bash
ceph osd set noout
ceph osd set nodown
ceph osd set norebalance
ceph osd set nobackfill
ceph osd set norecover
```

2. Scale down the Rook operator and Ceph deployments.

```bash
kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=0
```

Order matters—mons last:

```bash
kubectl -n rook-ceph scale deployment rook-ceph-osd-0 --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-osd-1 --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-osd-2 --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mgr-a --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mgr-b --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mgr-c --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mgr-d --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mon-a --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mon-b --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mon-c --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mon-d --replicas=0
```

3. Shutdown Talos nodes in ascending order of criticality:

```bash
talosctl shutdown -n <node-ip>
```

4. On restart, bring control-plane nodes back first, then reverse the Ceph scaling process, and finally clear Ceph flags.

Order matters—mons first:

```bash
kubectl -n rook-ceph scale deployment rook-ceph-mon-a --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mon-b --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mon-c --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mon-d --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mon-e --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mgr-a --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mgr-b --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mgr-c --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mgr-d --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-osd-0 --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-osd-1 --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-osd-2 --replicas=1
```

```bash
kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=1
```

```bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- bash
```

```bash
ceph osd unset noout
ceph osd unset nodown
ceph osd unset norebalance
ceph osd unset nobackfill
ceph osd unset norecover
```

## Rollback and Disaster Recovery

1. **Configuration Regression**

   - Revert the offending Git commit and trigger Flux reconciliation.
   - Reapply the last-known-good config from `talos/clusterconfig/`.

2. **Node Rebuild**

   - Wipe disks with the Talos installer, re-run provisioning, and reapply machine configs.
   - Restore labels and taints to align with node pool expectations.

3. **Control Plane Failure**

   - Restore etcd from the latest snapshot:

     ```bash
     talosctl etcd snapshot restore --endpoints <node-ip> --snapshot <path>
     ```

   - Update VIP or DNS entries if API endpoints move.

4. **Secrets Recovery**

   - Decrypt backups of `talos/talenv.sops.yaml` and `talos/talsecret.sops.yaml`.
   - Rotate Age identities if compromise is suspected; re-run `task talos:gen`.

5. **Disaster Scenario**
   - Rebuild control-plane nodes first, followed by storage workers and application workers.
   - Validate storage reattachment and Flux reconciliation before handing workloads back to product teams.

## Validation

- During provisioning: `talosctl health`, `talosctl kubeconfig --nodes <control-plane-ip>`.
- Post GitOps change: `talhelper genconfig --diff`, `flux get kustomizations cluster-machines -n flux-system`.
- Node readiness: `kubectl get nodes -o wide`, `kubectl describe node <hostname>`.
- Upgrade confirmation: `talosctl version -n <node-ip>`, `talosctl get machineconfig`.
- Storage validation: `kubectl -n rook-ceph get pods`, `ceph status`.

## Troubleshooting

### Node Reports `NotReady`

- Inspect kubelet status:

  ```bash
  kubectl describe node <hostname>
  talosctl logs -n <node-ip> kubelet
  talosctl logs -n <node-ip> containerd
  ```

- Validate Cilium components:

  ```bash
  talosctl get staticpod kube-system/cilium -n <node-ip>
  ```

### Talos API Unreachable

- Attempt health checks:

  ```bash
  talosctl health --nodes <node-ip>
  ```

- Retrieve the current machineconfig to confirm certificates:

  ```bash
  talosctl -n <node-ip> get machineconfig
  ```

- Compare NIC configuration with the overlay. Use OOB management for recovery if the API remains inaccessible.

### Storage Integration Issues

- Confirm Ceph node labels and CRUSH map expectations.
- Validate Talos disk presentation:

  ```bash
  talosctl -n <node-ip> ls /dev/disk/by-id
  ```

- Ensure encrypted volumes unlocked successfully via Talos events.

### Machineconfig Drift

- Detect differences:

  ```bash
  talhelper genconfig --diff
  talosctl -n <node-ip> get appliedconfiguration
  ```

- Reapply configs or rotate secrets as required.

## Escalation Guidance

- Post incidents in the platform on-call channel with Talos logs, Flux status, and recent Git commits.
- Engage hardware owners for physical failures or BMC access issues.
- Escalate to security for Age identity rotation or suspected credential compromise.
- Coordinate with the storage lead when Ceph maintenance flags remain set or OSDs fail to return.

## Talos Image Schematics

| Hardware Class            | Schematic ID                                                       | SecureBoot ISO                                                                                                                                  | Upgrade Image                                                                                                           |
| ------------------------- | ------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Bossgame E2 control plane | `7545fb734ed1aedc102a971aa833ae3927c260bd6cc70744469001bee8f8e1b6` | [Download](https://factory.talos.dev/image/7545fb734ed1aedc102a971aa833ae3927c260bd6cc70744469001bee8f8e1b6/v1.11.5/metal-amd64-secureboot.iso) | `factory.talos.dev/metal-installer-secureboot/7545fb734ed1aedc102a971aa833ae3927c260bd6cc70744469001bee8f8e1b6:v1.11.5` |
| MS-01 worker              | `7d51373a99be01395b499f21e0cdf3d27cca57c3feab356c20efe96a2df341bf` | [Download](https://factory.talos.dev/image/7d51373a99be01395b499f21e0cdf3d27cca57c3feab356c20efe96a2df341bf/v1.11.5/metal-amd64-secureboot.iso) | `factory.talos.dev/metal-installer-secureboot/7d51373a99be01395b499f21e0cdf3d27cca57c3feab356c20efe96a2df341bf:v1.11.5` |

Reference the Talos SecureBoot documentation for ISO usage: <https://www.talos.dev/v1.11/talos-guides/install/bare-metal-platforms/secureboot/>

Additional assets:

- SecureBoot UKI: <https://factory.talos.dev/image/1d6296ab0966f9bd87ec25c8fc39f15b15768c33fc1cccd52a8c098a930fbafb/v1.11.5/metal-amd64-secureboot-uki.efi>

## Secrets and Credentials

- Generate or rotate Talos secrets via `task talos:gen`.
- Store decrypted outputs only in secure local paths; never commit rendered secrets.
- Age identities should be rotated annually or after suspected compromise.

## Log Gathering

| Target                    | Command                                 |
| ------------------------- | --------------------------------------- |
| Kernel ring buffer        | `talosctl -n <node-ip> dmesg`           |
| Talos service logs        | `talosctl -n <node-ip> logs`            |
| Kubernetes component logs | `talosctl -n <node-ip> logs -k`         |
| etcd                      | `talosctl -n <node-ip> logs etcd`       |
| containerd                | `talosctl -n <node-ip> logs containerd` |

<!-- markdownlint-enable MD013 -->

Leverage `task dev-env:priv-pod node=<node>` to launch a privileged debugging pod when deeper inspection is required inside Kubernetes.
