# Velero Backup AWS S3 Terraform Workspace

## Overview

This Terraform workspace provisions S3 buckets and IAM resources for Velero backups with cross-region replication for enhanced disaster recovery. It creates a primary bucket in the specified region and a replica bucket in a secondary region, with automatic replication of backup data to DEEP_ARCHIVE storage for cost-effective long-term retention.

## Usage

### Terraform Cloud Variable Sets

Before triggering any runs, configure a Variable Set in Terraform Cloud:

1. In the Terraform Cloud UI, navigate to **Organization Settings → Variable Sets**.
2. Create or select a Variable Set for **velero-backup**.
3. Add the following `terraform`-category variables:
   - `project` (e.g., `spruyt-labs`)
   - `environment` (e.g., `prod`)
   - `aws_region` (e.g., `ap-southeast-4`)
4. Attach the Variable Set to the **velero-backup** workspace.

### Triggering Runs

Push any change to the configured VCS branch (e.g., `main`); Terraform Cloud will automatically queue a run for the **velero-backup** workspace.

### Post-Run Actions

After the run completes, note the outputs for:

- S3 bucket name
- IAM user
- Access key ID
- Secret access key (sensitive)

### Kubernetes Secret

Velero reads the credentials from the `velero-secret` Secret, stored SOPS-encrypted in `cluster/apps/velero/velero/app/velero-secret.sops.yaml`. Edit it with `sops` and set the `cloud` key to an AWS credentials file:

```ini
[default]
aws_access_key_id = <access_key_id>
aws_secret_access_key = <secret_access_key>
```

### Bucket Names

If the bucket name or region changes, update `cluster/apps/velero/velero/resources/backup-storage-location.yaml` (bucket and region) and `volume-snapshot-location.yaml` (region).

## Security & Compliance

- S3 bucket is versioned and encrypted.
- Public access is fully blocked.
- IAM user has least-privilege access to the bucket.

## Outputs

- `velero_backup_bucket`: S3 bucket name
- `velero_iam_user`: IAM username
- `velero_iam_access_key_id`: Access key ID
- `velero_iam_secret_access_key`: Secret access key (sensitive)
