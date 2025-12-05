# AWS OIDC Provider Module

## Overview

This Terraform module provisions an AWS IAM OpenID Connect (OIDC) Provider to enable workload identity authentication between Terraform Cloud and AWS. The OIDC provider allows Terraform Cloud workspaces to assume AWS IAM roles without requiring long-lived AWS credentials.

## Prerequisites

- AWS account with permissions to create IAM OIDC providers
- Terraform Cloud organization with workload identity enabled
- Network access to Terraform Cloud endpoints for certificate validation

## Operation

### Deployment Procedure

1. Include this module in your Terraform configuration:

```hcl
module "oidc_provider" {
  source = "./modules/aws-oidc-provider"

  tfc_hostname     = "app.terraform.io"
  tfc_aws_audience = "aws.workload.identity"
  aws_region       = "ap-southeast-4"
}
```

2. Run `terraform init` and `terraform apply` to create the OIDC provider.

### Variables

| Variable           | Type   | Default                   | Description                             |
| ------------------ | ------ | ------------------------- | --------------------------------------- |
| `tfc_hostname`     | string | `"app.terraform.io"`      | Terraform Cloud hostname                |
| `tfc_aws_audience` | string | `"aws.workload.identity"` | OIDC audience for AWS workload identity |
| `aws_region`       | string | `"ap-southeast-4"`        | AWS region for the OIDC provider        |

### Outputs

| Output              | Description                      |
| ------------------- | -------------------------------- |
| `oidc_provider_arn` | ARN of the created OIDC provider |

### Monitoring Commands

- Verify OIDC provider creation: `aws iam get-open-id-connect-provider --open-id-connect-provider-arn <arn>`
- Check Terraform Cloud integration: Review workspace settings in Terraform Cloud UI

### Cross-Service Dependencies

- **Depends on**: Terraform Cloud organization configuration
- **Depended by**: AWS IAM roles that use workload identity, Terraform Cloud workspaces

## Troubleshooting

### OIDC Provider Creation Fails

- Verify AWS permissions include `iam:CreateOpenIDConnectProvider`
- Check that the Terraform Cloud hostname is accessible for certificate retrieval
- Ensure no existing OIDC provider conflicts with the thumbprint

### Workload Identity Authentication Issues

- Confirm the OIDC provider ARN is correctly referenced in IAM role trust policies
- Verify the audience value matches Terraform Cloud configuration
- Check Terraform Cloud workspace has workload identity enabled

## Maintenance

### Updates

- Monitor Terraform Cloud certificate rotation and update thumbprints as needed
- Review AWS IAM access logs for authentication patterns
- Audit OIDC provider usage across IAM roles periodically

### Security Considerations

- OIDC providers enable passwordless authentication but require proper role trust policies
- Regularly rotate and audit IAM roles that depend on this provider
- Monitor for unusual authentication patterns in AWS CloudTrail

## References

- [Terraform Cloud Workload Identity](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration)
- [AWS IAM OIDC Providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
