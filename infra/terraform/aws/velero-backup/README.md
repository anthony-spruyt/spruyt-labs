# Velero Backup AWS S3 Terraform Workspace

## Overview

This Terraform workspace provisions an S3 bucket and IAM user for Velero backups.

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

Create a Kubernetes secret in the `velero` namespace with the AWS credentials:

```sh
kubectl -n velero create secret generic velero-aws-creds \
  --from-literal=cloud=<access_key_id>:<secret_access_key>
```

Or, for the standard Velero format, create a file `credentials-velero`:

```ini
[default]
aws_access_key_id = <access_key_id>
aws_secret_access_key = <secret_access_key>
```

Then:

```sh
kubectl -n velero create secret generic velero-aws-creds --from-file=cloud=credentials-velero
```

### Helm Values

Update your Velero Helm values (`values.yaml`) with the bucket name, region, and secret name.

## Security & Compliance

- S3 bucket is versioned and encrypted.
- Public access is fully blocked.
- IAM user has least-privilege access to the bucket.

## Outputs

- `velero_backup_bucket`: S3 bucket name
- `velero_iam_user`: IAM username
- `velero_iam_access_key_id`: Access key ID
- `velero_iam_secret_access_key`: Secret access key (sensitive)
