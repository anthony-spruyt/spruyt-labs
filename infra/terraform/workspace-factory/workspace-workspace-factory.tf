# data "tfe_project" "tfc_project" {
#   name         = var.tfc_project_name
#   organization = var.tfc_organization_name
# }
#
# resource "tfe_workspace" "workspace_factory" {
#   name              = var.workspace_factory_tfc_workspace_name
#   organization      = var.tfc_organization_name
#   project_id        = data.tfe_project.tfc_project.id
#   working_directory = var.workspace_factory_tfc_working_directory
#   trigger_patterns = [
#     var.workspace_factory_tfc_trigger_pattern
#   ]
#   vcs_repo {
#     branch                     = var.tfc_vcs_repo_branch
#     github_app_installation_id = var.tfc_vcs_repo_github_app_installation_id
#     identifier                 = var.tfc_vcs_repo_identifier
#     ingress_submodules         = var.tfc_vcs_repo_ingress_submodules
#   }
# }
