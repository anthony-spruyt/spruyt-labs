# Cloud Native PostgreSQL Backup AWS S3 Terraform Workspace

This Terraform workspace provisions an S3 bucket and IAM user for Cloud Native PostgreSQL backups.

## Usage

### Terraform Cloud Variable Sets

Before triggering any runs, configure a Variable Set in Terraform Cloud:

1. In the Terraform Cloud UI, navigate to **Organization Settings → Variable Sets**.
2. Create or select a Variable Set for **cnpg-backup**.
3. Add the following `terraform`-category variables:
   - `project` (e.g., `spruyt-labs`)
   - `environment` (e.g., `prod`)
   - `aws_region` (e.g., `ap-southeast-4`)
4. Attach the Variable Set to the **cnpg-backup** workspace.

### Triggering Runs

Push any change to the configured VCS branch (e.g., `main`); Terraform Cloud will automatically queue a run for the **cnpg-backup** workspace.

### Post-Run Actions

After the run completes, note the outputs for:

- S3 bucket name
- IAM user
- Access key ID
- Secret access key (sensitive)

## Security & Compliance

- S3 bucket is versioned and encrypted.
- Public access is fully blocked.
- IAM user has least-privilege access to the bucket.

## Outputs

- `cnpg_backup_bucket`: S3 bucket name
- `cnpg_iam_user`: IAM username
- `cnpg_iam_access_key_id`: Access key ID
- `cnpg_iam_secret_access_key`: Secret access key (sensitive)
