
locals {
  ceph_objectstore_bucket_pattern = "arn:aws:s3:::spruyt-labs-${var.aws_account_id}-prod-ceph-*"
}

data "aws_iam_policy_document" "ceph_objectstore_aws_iam_policy" {
  version = "2012-10-17"
  statement {
    sid    = "CephObjectStoreTerraformAccess"
    effect = "Allow"
    actions = [
      "s3:*",
    ]
    resources = [
      local.ceph_objectstore_bucket_pattern,
      "${local.ceph_objectstore_bucket_pattern}/*"
    ]
  }
}

module "ceph-objectstore" {
  source                                  = "./modules/aws-workspace"
  count                                   = 0
  aws_iam_policy_document                 = data.aws_iam_policy_document.ceph_objectstore_aws_iam_policy.json
  aws_region                              = var.aws_region
  tfc_trigger_pattern                     = var.ceph_objectstore_tfc_trigger_pattern
  tfc_vcs_repo_branch                     = var.tfc_vcs_repo_branch
  tfc_vcs_repo_github_app_installation_id = var.tfc_vcs_repo_github_app_installation_id
  tfc_vcs_repo_identifier                 = var.tfc_vcs_repo_identifier
  tfc_organization_name                   = var.tfc_organization_name
  tfc_project_name                        = var.tfc_project_name
  tfc_working_directory                   = var.ceph_objectstore_tfc_working_directory
  tfc_workspace_name                      = var.ceph_objectstore_tfc_workspace_name
  tfc_vcs_repo_ingress_submodules         = var.tfc_vcs_repo_ingress_submodules
  tfc_vcs_repo_oauth_token_id             = var.tfc_vcs_repo_oauth_token_id
  tfc_vcs_repo_tags_regex                 = var.tfc_vcs_repo_tags_regex
}

module "ceph_objectstore" {
  source                                  = "./modules/aws-workspace"
  aws_iam_policy_document                 = data.aws_iam_policy_document.ceph_objectstore_aws_iam_policy.json
  aws_region                              = var.aws_region
  tfc_trigger_pattern                     = var.ceph_objectstore_tfc_trigger_pattern
  tfc_vcs_repo_branch                     = var.tfc_vcs_repo_branch
  tfc_vcs_repo_github_app_installation_id = var.tfc_vcs_repo_github_app_installation_id
  tfc_vcs_repo_identifier                 = var.tfc_vcs_repo_identifier
  tfc_organization_name                   = var.tfc_organization_name
  tfc_project_name                        = var.tfc_project_name
  tfc_working_directory                   = var.ceph_objectstore_tfc_working_directory
  tfc_workspace_name                      = var.ceph_objectstore_tfc_workspace_name
  tfc_vcs_repo_ingress_submodules         = var.tfc_vcs_repo_ingress_submodules
  tfc_vcs_repo_oauth_token_id             = var.tfc_vcs_repo_oauth_token_id
  tfc_vcs_repo_tags_regex                 = var.tfc_vcs_repo_tags_regex
}
