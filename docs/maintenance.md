# Cluster Maintenance Guide

Regular maintenance procedures for the Talos Linux Kubernetes cluster.

## Pre-Change Verification

Complete these verification steps before submitting changes to ensure cluster stability.

### Terraform Infrastructure Changes

1. Format and validate:

   ```bash
   terraform fmt
   terraform validate
   ```

1. Run plan and capture output:

   ```bash
   terraform plan -out plan.tfplan
   ```

1. Request review with plan output attached

1. Apply with exact plan reviewed:

   ```bash
   terraform apply plan.tfplan
   ```

1. Confirm state file synchronization and monitor for drift

### Talos Configuration Changes

1. Assess cluster health before changes:

   ```bash
   talosctl health
   talosctl logs -f kubelet
   ```

1. Diff intended vs live config:

   ```bash
   talosctl config diff
   ```

1. Apply changes:

   ```bash
   talosctl apply-config --insecure --nodes <target> --file <config.yaml>
   ```

1. Verify post-change status:

   ```bash
   talosctl health
   kubectl get nodes
   ```

## Day-2 Operations

- Scale Talos workloads safely using the graceful shutdown pattern in [talos/README.md](../talos/README.md)
- Launch privileged pods for node diagnostics: `task dev-env:priv-pod node=<node>`

## Renovate Dependency Management

Renovate automates dependency updates. See [.claude/rules/renovate.md](../.claude/rules/renovate.md) for details.

### Quarterly Maintenance

1. Review the Renovate configuration file `.github/renovate.json5`
1. Monitor update success rates and system stability
1. Audit manager coverage for all dependency types

### Troubleshooting Updates

| Issue            | Solution                                               |
| ---------------- | ------------------------------------------------------ |
| Failed updates   | Review PR comments; adjust stabilityDays or groupings  |
| Missing deps     | Audit manager configurations and file patterns         |
| Stability issues | Roll back by reverting commits; increase stabilityDays |
| Config errors    | Validate JSON5 syntax; test with Renovate dry-run      |

## Certificate Renewal

Certificates are managed by cert-manager and auto-renew.

## Storage Maintenance

### Ceph Health

```bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd status
```

### Before Node Maintenance

```bash
# Set noout flag before taking node offline
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd set noout

# After node returns
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd unset noout
```

## Related

- [docs/disaster-recovery.md](disaster-recovery.md) - DR procedures
- [.claude/rules/](../.claude/rules/) - Claude agent rules
- [talos/README.md](../talos/README.md) - Talos-specific procedures
