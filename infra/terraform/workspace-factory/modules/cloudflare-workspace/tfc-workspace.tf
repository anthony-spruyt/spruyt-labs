data "tfe_project" "tfc_project" {
  name         = var.tfc_project_name
  organization = var.tfc_organization_name
}

resource "tfe_workspace" "my_workspace" {
  name              = var.tfc_workspace_name
  organization      = var.tfc_organization_name
  project_id        = data.tfe_project.tfc_project.id
  working_directory = var.tfc_working_directory
  trigger_patterns = [
    var.tfc_trigger_pattern
  ]
  vcs_repo {
    branch                     = var.tfc_vcs_repo_branch
    github_app_installation_id = var.tfc_vcs_repo_github_app_installation_id
    identifier                 = var.tfc_vcs_repo_identifier
    ingress_submodules         = var.tfc_vcs_repo_ingress_submodules
  }
  force_delete = true
}

resource "tfe_variable" "cloudflare_api_token" {
  workspace_id     = tfe_workspace.my_workspace.id
  key              = "CLOUDFLARE_API_TOKEN"
  value_wo         = var.cloudflare_api_token
  value_wo_version = var.tfc_variables_version
  category         = "env"
  sensitive        = true
  description      = "Cloudflare API token used by the provider."
}

resource "tfe_variable" "cloudflare_account_id" {
  workspace_id     = tfe_workspace.my_workspace.id
  key              = "cloudflare_account_id"
  value_wo         = var.cloudflare_account_id
  value_wo_version = var.tfc_variables_version
  category         = "terraform"
  sensitive        = true
  description      = "Cloudflare account ID."
}

resource "tfe_variable" "zone_name" {
  workspace_id     = tfe_workspace.my_workspace.id
  key              = "zone_name"
  value_wo         = var.cloudflare_zone_name
  value_wo_version = var.tfc_variables_version
  category         = "terraform"
  sensitive        = true
  description      = "Cloudflare zone (apex domain) name."
}

resource "tfe_variable" "dns_verification" {
  workspace_id     = tfe_workspace.my_workspace.id
  key              = "dns_verification"
  value_wo         = jsonencode(var.cloudflare_dns_verification)
  value_wo_version = var.tfc_variables_version
  category         = "terraform"
  hcl              = true
  sensitive        = true
  description      = "Per-domain DNS verification tokens and IDs."
}
