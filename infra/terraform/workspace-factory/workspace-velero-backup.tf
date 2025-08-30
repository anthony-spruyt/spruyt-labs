
locals {
  velero_backup_bucket_pattern = "arn:aws:s3:::spruyt-labs-${var.aws_account_id}-prod-velero-*"
}

data "aws_iam_policy_document" "velero_backup_aws_iam_policy" {
  version = "2012-10-17"
  statement {
    sid    = "VeleroS3TerraformAccess"
    effect = "Allow"
    actions = [
      "s3:*",
    ]
    resources = [
      local.velero_backup_bucket_pattern,
      "${local.velero_backup_bucket_pattern}/*"
    ]
  }
}

module "velero_backup" {
  source                                  = "./modules/aws-workspace"
  aws_iam_policy_document                 = data.aws_iam_policy_document.velero_backup_aws_iam_policy.json
  aws_region                              = var.aws_region
  tfc_trigger_pattern                     = var.velero_backup_tfc_trigger_pattern
  tfc_vcs_repo_branch                     = var.tfc_vcs_repo_branch
  tfc_vcs_repo_github_app_installation_id = var.tfc_vcs_repo_github_app_installation_id
  tfc_vcs_repo_identifier                 = var.tfc_vcs_repo_identifier
  tfc_organization_name                   = var.tfc_organization_name
  tfc_project_name                        = var.tfc_project_name
  tfc_working_directory                   = var.velero_backup_tfc_working_directory
  tfc_workspace_name                      = var.velero_backup_tfc_workspace_name
  tfc_vcs_repo_ingress_submodules         = var.tfc_vcs_repo_ingress_submodules
}
