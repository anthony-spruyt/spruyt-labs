variable "tfc_hostname" {
  type        = string
  description = "The hostname of the Terraform Cloud (TFC) or Terraform Enterprise (TFE) instance to use for workspace integration"
}

variable "tfc_organization_name" {
  type        = string
  description = "The name of the Terraform Cloud organization where the workspace will be created"
}

variable "tfc_project_name" {
  type        = string
  description = "The name of the Terraform Cloud project under which the workspace will be created"
}

variable "ceph_objectstore_tfc_workspace_name" {
  type        = string
  description = "The name of the Terraform Cloud workspace for Ceph Objectstore to create and connect to AWS"
}

variable "velero_backup_tfc_workspace_name" {
  type        = string
  description = "The name of the Terraform Cloud workspace for Velero backup to create and connect to AWS"
}

variable "aws_region" {
  type        = string
  description = "The AWS region in which to provision all resources"
}

variable "aws_account_id" {
  type        = string
  description = "The AWS account ID used for resource provisioning"
}

variable "ceph_objectstore_tfc_trigger_pattern" {
  type        = string
  description = "The regex pattern used to match VCS webhook triggers for the Ceph Objectstore workspace"
}

variable "tfc_vcs_repo_branch" {
  type        = string
  description = "The VCS repository branch that will trigger the Terraform Cloud workspace"
}

variable "tfc_vcs_repo_github_app_installation_id" {
  type        = string
  description = "The GitHub App installation ID used for VCS integration in the Terraform Cloud workspace"
}

variable "tfc_vcs_repo_identifier" {
  type        = string
  description = "The full VCS repository identifier (e.g., org/repo) for the Terraform Cloud workspace"
}

variable "ceph_objectstore_tfc_working_directory" {
  type        = string
  description = "The working directory within the VCS repository for the Ceph Objectstore Terraform Cloud workspace"
}

variable "velero_backup_tfc_trigger_pattern" {
  type        = string
  description = "The regex pattern used to match VCS webhook triggers for the Velero backup workspace"
}

variable "velero_backup_tfc_working_directory" {
  type        = string
  description = "The working directory within the VCS repository for the Velero backup Terraform Cloud workspace"
}

variable "tfc_vcs_repo_ingress_submodules" {
  type        = bool
  default     = false
  description = "Flag to enable support for VCS submodules in the repository for the workspace-factory workspace"
}

# variable "workspace_factory_tfc_workspace_name" {
#   type        = string
#   description = "The name of the Terraform Cloud workspace for the workspace-factory module"
# }
#
# variable "workspace_factory_tfc_working_directory" {
#   type        = string
#   description = "The working directory within the VCS repository for the workspace-factory Terraform Cloud workspace"
# }
#
# variable "workspace_factory_tfc_trigger_pattern" {
#   type        = string
#   description = "The regex pattern used to match VCS webhook triggers for the workspace-factory workspace"
# }
