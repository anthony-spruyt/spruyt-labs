data "aws_iam_policy_document" "ceph_objectstore_tfc_aws_iam_policy" {
  version = "2012-10-17"
  statement {
    sid    = "CephObjectstoreTerraformAccess"
    effect = "Allow"
    actions = [
      "*"
    ]
    resources = [
      "*"
    ]
  }
}

module "ceph_objectstore" {
  source                                  = "./modules/aws-workspace"
  aws_iam_policy_document                 = data.aws_iam_policy_document.ceph_objectstore_tfc_aws_iam_policy.json
  aws_region                              = var.aws_region
  tfc_trigger_pattern                     = var.ceph_objectstore_aws_tfc_trigger_pattern
  tfc_vcs_repo_branch                     = var.tfc_vcs_repo_branch
  tfc_vcs_repo_github_app_installation_id = var.tfc_vcs_repo_github_app_installation_id
  tfc_vcs_repo_identifier                 = var.tfc_vcs_repo_identifier
  tfc_organization_name                   = var.tfc_organization_name
  tfc_project_name                        = var.tfc_project_name
  tfc_working_directory                   = var.ceph_objectstore_aws_tfc_working_directory
  tfc_workspace_name                      = var.ceph_objectstore_aws_tfc_workspace_name
  tfc_vcs_repo_ingress_submodules         = var.tfc_vcs_repo_ingress_submodules
  oidc_provider_arn                       = module.aws_oidc_provider.aws_oidc_provider_arn
  oidc_provider_client_id_list            = module.aws_oidc_provider.aws_oidc_provider_client_id_list
}
