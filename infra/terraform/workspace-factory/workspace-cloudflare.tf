module "cloudflare" {
  source                                  = "./modules/cloudflare-workspace"
  tfc_trigger_pattern                     = var.cloudflare_tfc_trigger_pattern
  tfc_vcs_repo_branch                     = var.tfc_vcs_repo_branch
  tfc_vcs_repo_github_app_installation_id = var.tfc_vcs_repo_github_app_installation_id
  tfc_vcs_repo_identifier                 = var.tfc_vcs_repo_identifier
  tfc_organization_name                   = var.tfc_organization_name
  tfc_project_name                        = var.tfc_project_name
  tfc_working_directory                   = var.cloudflare_tfc_working_directory
  tfc_workspace_name                      = var.cloudflare_tfc_workspace_name
  tfc_vcs_repo_ingress_submodules         = var.tfc_vcs_repo_ingress_submodules
  cloudflare_api_token                    = var.cloudflare_api_token
  cloudflare_account_id                   = var.cloudflare_account_id
  cloudflare_zone_name                    = var.cloudflare_zone_name
  cloudflare_dns_verification             = var.cloudflare_dns_verification
}
