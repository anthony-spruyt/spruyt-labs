# External Secrets AWS IAM Terraform Workspace

## Overview

This Terraform workspace provisions AWS IAM resources for the External Secrets Operator in the Kubernetes cluster. It creates IAM users and policies that allow the external-secrets pods to access AWS services for retrieving secrets.

**Note**: Most resources are currently commented out. Uncomment the code in `main.tf` when ready to provision full external secrets integration.

## Prerequisites

- AWS account with IAM permissions
- External Secrets Operator deployed in Kubernetes cluster
- Terraform Cloud workspace access

## Operation

### Deployment Procedure

1. Uncomment desired resources in `main.tf`
2. Configure Terraform Cloud variable set with required variables
3. Run `terraform init` and `terraform apply`

### Variables

| Variable      | Type   | Description                 |
| ------------- | ------ | --------------------------- |
| `project`     | string | Project tag and name prefix |
| `environment` | string | Environment tag             |

### Outputs

| Output                  | Description                       |
| ----------------------- | --------------------------------- |
| `iam_user_name`         | IAM username for external secrets |
| `iam_user_arn`          | IAM user ARN                      |
| `iam_access_key_id`     | Access key ID (sensitive)         |
| `iam_secret_access_key` | Secret access key (sensitive)     |

### Monitoring Commands

- Check IAM user: `aws iam get-user --user-name external-secrets`
- Verify access keys: `aws iam list-access-keys --user-name external-secrets`
- Monitor CloudTrail: `aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=external-secrets`

### Cross-Service Dependencies

- **Depends on**: AWS account with IAM permissions
- **Depended by**: External Secrets Operator (`cluster/apps/external-secrets/`), Kubernetes secrets management

## Troubleshooting

### IAM User Creation Fails

- Verify AWS account limits for IAM users
- Check permissions for IAM user creation
- Ensure unique username (IAM usernames are unique per account)

### Access Key Issues

- Confirm access keys are properly stored in Kubernetes secrets
- Verify External Secrets Operator can access the keys
- Check CloudTrail for authentication failures

### Permission Problems

- Review IAM policies attached to the user
- Ensure policies allow access to required AWS services
- Validate resource ARNs in policy statements

## Maintenance

### Updates

- Rotate access keys regularly for security
- Review and update IAM policies based on access patterns
- Monitor AWS costs associated with IAM resources

### Security Considerations

- Store access keys securely in Kubernetes secrets
- Use least-privilege IAM policies
- Regularly audit access patterns and rotate credentials

## References

- [External Secrets Operator](https://external-secrets.io/)
- [AWS IAM Users](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users.html)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)
- [AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
