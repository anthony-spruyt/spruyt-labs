# Velero Backup AWS S3 Terraform Workspace

This Terraform workspace provisions an S3 bucket and IAM user for Velero backups.

## Usage

1. Initialize and apply the workspace:

   ```sh
   terraform init
   terraform apply -var="velero_backup_bucket=<your-unique-bucket-name>" -var="aws_region=<your-region>"
   ```

2. After apply, note the outputs for:

   - S3 bucket name
   - IAM user
   - Access key ID
   - Secret access key (sensitive)

3. Create a Kubernetes secret in the `velero` namespace with the AWS credentials:

   ```sh
   kubectl -n velero create secret generic velero-aws-creds \
     --from-literal=cloud=<aws_access_key_id>:<aws_secret_access_key>
   ```

   Or, for the standard Velero format, create a file `credentials-velero`:

   ```
   [default]
   aws_access_key_id = <access_key_id>
   aws_secret_access_key = <secret_access_key>
   ```

   Then:

   ```sh
   kubectl -n velero create secret generic velero-aws-creds --from-file=cloud=credentials-velero
   ```

4. Update your Velero Helm values (`values.yaml`) with the bucket name, region, and secret name.

## Security & Compliance

- S3 bucket is versioned and encrypted.
- Public access is fully blocked.
- IAM user has least-privilege access to the bucket.

## Outputs

- `velero_backup_bucket`: S3 bucket name
- `velero_iam_user`: IAM user name
- `velero_iam_access_key_id`: Access key ID
- `velero_iam_secret_access_key`: Secret access key (sensitive)

## Linting

Run [Checkov](https://www.checkov.io/) for security best practices:

```sh
checkov -d .
```
