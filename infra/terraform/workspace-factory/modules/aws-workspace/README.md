# AWS Workspace Module

## Overview

This Terraform module creates a Terraform Cloud workspace with AWS workload identity integration. It provisions the necessary AWS IAM roles, policies, and Terraform Cloud workspace configuration to enable secure, credential-less authentication between Terraform Cloud runs and AWS services.

## Prerequisites

- Terraform Cloud organization with appropriate permissions
- AWS account with IAM role creation permissions
- GitHub repository with Terraform Cloud GitHub App installed
- OIDC provider already configured (see aws-oidc-provider module)

## Operation

### Deployment Procedure

1. Include this module in your Terraform configuration:

```hcl
module "workspace" {
  source = "./modules/aws-workspace"

  tfc_organization_name                   = "your-org"
  tfc_project_name                        = "your-project"
  tfc_workspace_name                      = "example-workspace"
  aws_iam_policy_document                 = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:*"]
      Resource = ["*"]
    }]
  })
  tfc_working_directory                  = "infra/terraform/aws/example"
  tfc_trigger_pattern                    = "infra/terraform/aws/example/**"
  tfc_vcs_repo_branch                    = "main"
  tfc_vcs_repo_github_app_installation_id = "12345"
  tfc_vcs_repo_identifier                = "your-org/your-repo"
  oidc_provider_arn                      = module.oidc_provider.oidc_provider_arn
  oidc_provider_client_id_list           = ["aws.workload.identity"]
}
```

2. Run `terraform init` and `terraform apply` to create the workspace and IAM resources.

### Variables

| Variable                                  | Type         | Default | Description                          |
| ----------------------------------------- | ------------ | ------- | ------------------------------------ |
| `tfc_organization_name`                   | string       | -       | Terraform Cloud organization name    |
| `tfc_project_name`                        | string       | -       | Terraform Cloud project name         |
| `tfc_workspace_name`                      | string       | -       | Workspace name                       |
| `aws_iam_policy_document`                 | string       | -       | JSON-encoded IAM policy for the role |
| `tfc_working_directory`                   | string       | -       | Working directory in VCS repo        |
| `tfc_trigger_pattern`                     | string       | -       | VCS trigger pattern                  |
| `tfc_vcs_repo_branch`                     | string       | -       | VCS repository branch                |
| `tfc_vcs_repo_github_app_installation_id` | string       | -       | GitHub App installation ID           |
| `tfc_vcs_repo_identifier`                 | string       | -       | Full repository identifier           |
| `oidc_provider_arn`                       | string       | -       | OIDC provider ARN                    |
| `oidc_provider_client_id_list`            | list(string) | -       | OIDC provider client IDs             |

### Outputs

| Output           | Description                            |
| ---------------- | -------------------------------------- |
| `workspace_id`   | Terraform Cloud workspace ID           |
| `iam_role_arn`   | AWS IAM role ARN for workload identity |
| `iam_policy_arn` | AWS IAM policy ARN                     |

### Monitoring Commands

- Check workspace status: `terraform workspace show` (in workspace directory)
- Verify IAM role: `aws iam get-role --role-name tfc-role-<workspace-name>`
- Monitor runs: Check Terraform Cloud UI or use TFC API

## Troubleshooting

### Workspace Creation Fails

- Verify Terraform Cloud API token has workspace creation permissions
- Check that the project exists in Terraform Cloud
- Ensure GitHub App is properly installed on the repository

### IAM Role Authentication Issues

- Confirm OIDC provider ARN is correct and provider exists
- Verify the trust policy allows the correct workspace and run phases
- Check that workload identity is enabled in Terraform Cloud

### VCS Integration Problems

- Validate GitHub App installation ID is correct
- Ensure repository identifier follows org/repo format
- Check that the specified branch exists

## Maintenance

### Updates

- Monitor IAM role usage and access patterns in AWS CloudTrail
- Review and rotate IAM policies as needed for least privilege
- Update workspace settings when repository structure changes

### Security Considerations

- Regularly audit IAM policies for excessive permissions
- Monitor Terraform Cloud run logs for authentication failures
- Ensure workspace deletion removes associated IAM resources

## References

- [Terraform Cloud Workload Identity](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration)
- [Terraform Cloud API](https://developer.hashicorp.com/terraform/cloud-docs/api-docs)
- [AWS IAM Roles for OIDC](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
