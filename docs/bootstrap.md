# Cluster Bootstrap Guide

This guide covers the one-time initial deployment of the Talos Linux Kubernetes cluster.

## Hardware Requirements

| Component | Control Plane (Bossgame E2) | Workers (MS-01) |
| --------- | --------------------------- | --------------- |
| CPU       | 4+ cores, 8+ threads        | 4+ cores        |
| Memory    | 16GB min, 32GB recommended  | 16GB min        |
| Storage   | 256GB NVMe + Ceph OSDs      | 256GB NVMe      |
| Network   | 1GbE min, 2.5GbE preferred  | 1GbE min        |

## Bootstrap Procedure

### Phase 1: Repository and Tooling Setup

1. **Clone repository** and enter devcontainer:

   ```bash
   git clone https://github.com/anthony-spruyt/spruyt-labs.git
   cd spruyt-labs
   # Open in VS Code with devcontainer
   ```

2. **Install required tooling**:

   ```bash
   task dev-env:install-age
   task dev-env:install-flux
   task dev-env:install-talosctl
   ```

3. **Decrypt secrets** (requires Age identity):

   ```bash
   # Ensure AGE_IDENTITY environment variable is set
   task sops:decrypt
   ```

### Phase 2: Infrastructure Preparation

1. **Bootstrap Terraform Cloud workspaces**:

   ```bash
   cd infra/terraform/workspace-factory
   terraform init
   terraform plan -out plan.tfplan
   terraform apply plan.tfplan
   ```

2. **Configure Terraform variable sets** in Terraform Cloud for each workspace

3. **Provision AWS infrastructure** (if using cloud backups):

   ```bash
   cd infra/terraform/aws/velero-backup
   terraform init
   terraform plan -out plan.tfplan
   terraform apply plan.tfplan
   ```

### Phase 3: Talos Configuration Generation

1. **Update talconfig.yaml** with node specifications:

   ```yaml
   clusterName: spruyt-labs
   endpoint: https://<KUBEAPI_VIP>:6443
   nodes:
     - hostname: <node-hostname>
       ipAddress: <node-ip>
       controlPlane: true
       schematic: <schematic-id>
   ```

2. **Generate Talos secrets**:

   ```bash
   task talos:gen
   ```

3. **Generate machine configurations**:

   ```bash
   talhelper genconfig
   ```

### Phase 4: Node Provisioning

1. **Download Talos installer ISOs** from [Talos Image Factory](https://factory.talos.dev/)

2. **Boot first control plane node** with Talos ISO

3. **Apply configuration**:

   ```bash
   talosctl apply-config --insecure --nodes <node-ip> \
     --file talos/clusterconfig/<node-hostname>.yaml
   ```

4. **Bootstrap Kubernetes**:

   ```bash
   talosctl bootstrap --nodes <first-control-plane-ip>
   ```

5. **Verify cluster**:

   ```bash
   talosctl health --nodes <control-plane-ip>
   kubectl get nodes
   ```

6. **Repeat for remaining nodes** (control plane first, then workers)

### Phase 5: Flux Bootstrap

1. **Install Flux CLI** and bootstrap:

   ```bash
   flux bootstrap github \
     --owner=anthony-spruyt \
     --repository=spruyt-labs \
     --branch=main \
     --path=cluster/flux \
     --personal
   ```

2. **Monitor bootstrap**:

   ```bash
   flux get kustomizations -n flux-system
   ```

3. **Verify cluster components**:

   ```bash
   kubectl get pods -A
   ```

### Phase 6: Post-Bootstrap Configuration

1. **Configure external DNS** for ingress domains
2. **Set up certificate management** with cert-manager
3. **Deploy monitoring stack** (VictoriaMetrics, Vector, Grafana)
4. **Configure backup solutions** (Velero, CNPG backups)
5. **Test cluster functionality**:
   - Deploy test application
   - Verify ingress and TLS
   - Test storage provisioning
   - Validate monitoring and alerting

## Validation Checklist

- [ ] All nodes report Ready status
- [ ] Flux kustomizations are reconciled
- [ ] Core services (Cilium, cert-manager, external-dns) are running
- [ ] Ingress controller accessible
- [ ] Storage classes available
- [ ] Monitoring dashboards accessible
- [ ] Backup jobs scheduled

## Related

- [talos/README.md](../talos/README.md) - Talos configuration details
- [infra/terraform/](../infra/terraform/) - Terraform infrastructure
