# Ceph Object Store AWS S3 Terraform Workspace

## Overview

This Terraform workspace provisions AWS S3 object storage resources and IAM integration for use by Rook Ceph in the Kubernetes cluster. The workspace creates encrypted, versioned S3 buckets with appropriate lifecycle policies for Ceph object storage operations.

**Note**: This workspace is currently disabled (all resources commented out). Uncomment the code in `main.tf` and `variables.tf` when ready to provision Ceph object storage.

## Prerequisites

- AWS account with S3 and KMS permissions
- Terraform Cloud workspace access
- Rook Ceph cluster deployed and configured

## Operation

### Deployment Procedure

1. Uncomment all code in `main.tf` and `variables.tf`
2. Configure Terraform Cloud variable set with required variables
3. Run `terraform init` and `terraform apply`

### Variables

| Variable      | Type   | Default            | Description                     |
| ------------- | ------ | ------------------ | ------------------------------- |
| `project`     | string | `"spruyt-labs"`    | Project tag and name prefix     |
| `environment` | string | `"prod"`           | Environment tag and name suffix |
| `aws_region`  | string | `"ap-southeast-4"` | AWS region for resources        |

### Outputs

| Output        | Description                            |
| ------------- | -------------------------------------- |
| `bucket_name` | S3 bucket name for Ceph object storage |
| `bucket_arn`  | S3 bucket ARN                          |
| `kms_key_arn` | KMS key ARN for bucket encryption      |

### Monitoring Commands

- Check bucket status: `aws s3 ls s3://<bucket-name>`
- Verify encryption: `aws s3api get-bucket-encryption --bucket <bucket-name>`
- Monitor lifecycle: `aws s3api get-bucket-lifecycle-configuration --bucket <bucket-name>`

## Troubleshooting

### Bucket Creation Fails

- Verify AWS region supports required S3 features
- Check account limits for S3 buckets and KMS keys
- Ensure unique bucket name (globally unique across AWS)

### Encryption Issues

- Confirm KMS key policy allows S3 service access
- Verify KMS key is in the same region as the bucket
- Check CloudTrail for KMS access denied events

### Lifecycle Policy Problems

- Validate lifecycle configuration syntax
- Ensure storage class transitions are supported in the region
- Monitor S3 access logs for policy application

## Maintenance

### Updates

- Monitor S3 usage and costs regularly
- Review and update lifecycle policies based on access patterns
- Rotate KMS keys according to security policies

### Security Considerations

- Regularly audit bucket access logs
- Monitor for unusual access patterns
- Ensure encryption keys are properly rotated

## References

- [Rook Ceph Object Storage](https://rook.io/docs/rook/latest/Storage-Configuration/Object-Storage-RGW/object-storage/)
- [AWS S3 Bucket Encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-encryption.html)
- [AWS S3 Lifecycle Policies](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
