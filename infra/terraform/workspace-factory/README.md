# Terraform Workspace Factory

## Overview

This Terraform configuration bootstraps Terraform Cloud workspaces for AWS-based infrastructure using Workload Identity authentication.

## Prerequisites

- Terraform CLI v1.13 or later
- Terraform Cloud API token with permission to manage workspaces
- AWS IAM permissions to create roles and policies

## Workspaces Managed

| Name             | Purpose                                                               |
| ---------------- | --------------------------------------------------------------------- |
| ceph-objectstore | AWS Rook Ceph S3 object store for the Spruyt Labs cluster             |
| velero-backup    | S3 bucket and IAM user for Velero backups using AWS Workload Identity |

## Configuration

Update the variables file [variables.auto.tfvars](variables.auto.tfvars), for example:

```hcl
aws_account_id                          = "<AWS account ID>"
aws_region                              = "<AWS region>"
tfc_hostname                            = "app.terraform.io"
tfc_aws_audience                        = "aws.workload.identity"
tfc_organization_name                   = "<Terraform Cloud organization>"
tfc_project_name                        = "<Terraform Cloud project>"
tfc_vcs_repo_identifier                 = "<VCS repo identifier>"
tfc_vcs_repo_branch                     = "<VCS branch>"
tfc_vcs_repo_github_app_installation_id = "<GitHub App installation ID>"

ceph_objectstore_tfc_workspace_name     = "ceph-objectstore"
ceph_objectstore_tfc_working_directory  = "infra/terraform/aws/ceph-objectstore"
ceph_objectstore_tfc_trigger_pattern    = "infra/terraform/aws/ceph-objectstore/**"

velero_backup_tfc_workspace_name        = "velero-backup"
velero_backup_tfc_working_directory     = "infra/terraform/aws/velero-backup"
velero_backup_tfc_trigger_pattern       = "infra/terraform/aws/velero-backup/**"
```

## Usage

### Terraform Cloud Variable Sets

Before triggering any runs, configure a Variable Set in Terraform Cloud:

1. In the Terraform Cloud UI, navigate to **Organization Settings → Variable Sets**.
2. Create or select a Variable Set for this workspace.
3. Add the following **terraform**-category variables:
   - `aws_account_id`
   - `aws_region`
   - `tfc_hostname`
   - `tfc_aws_audience`
   - `tfc_organization_name`
   - `tfc_project_name`
   - `tfc_vcs_repo_identifier`
   - `tfc_vcs_repo_branch`
   - `tfc_vcs_repo_github_app_installation_id`
4. Attach the Variable Set to the **workspace-factory** workspace.

### Triggering Runs

Push any changes to the configured VCS branch (for example, `main`); Terraform Cloud will automatically queue runs for all configured workspaces.

### Post-Run Actions

After runs complete, review the following outputs in the Terraform Cloud UI or via the Terraform CLI:

- Other workspace-specific outputs in [outputs.tf](outputs.tf)

## Linting

Linting is automated via the GitHub Actions superlinter workflow, which includes Checkov, TFLint, and other Terraform security and style checks. Issues will be reported on pull requests.
