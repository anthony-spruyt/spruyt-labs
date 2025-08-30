variable "tfc_aws_audience" {
  type        = string
  default     = "aws.workload.identity"
  description = "The audience value to use in AWS workload identity tokens for Terraform Cloud"
}

variable "tfc_hostname" {
  type        = string
  default     = "app.terraform.io"
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

variable "tfc_workspace_name" {
  type        = string
  description = "The name of the Terraform Cloud workspace to create and connect to AWS"
}

variable "aws_region" {
  type        = string
  default     = "ap-southeast-4" # ap-southeast-2 = Sydney ; ap-southeast-4 = Melbourne
  description = "The AWS region in which to provision all resources"
}

variable "aws_iam_policy_document" {
  type        = string
  description = "The JSON-encoded AWS IAM policy document to be created and attached to the workload identity role"
}

variable "tfc_working_directory" {
  type        = string
  description = "The working directory within the VCS repository for the Terraform Cloud workspace"
}

variable "tfc_trigger_pattern" {
  type        = string
  description = "The regex pattern used to match VCS webhook triggers for this workspace"
}

variable "tfc_vcs_repo_branch" {
  type        = string
  description = "The VCS repository branch that will trigger the Terraform Cloud workspace"
}

variable "tfc_vcs_repo_github_app_installation_id" {
  type        = string
  description = "The Github app installation ID for the Terraform cloud workspace"
}

variable "tfc_vcs_repo_identifier" {
  type        = string
  description = "The full GitHub repository identifier (e.g., org/repo) for the Terraform Cloud workspace"
}

variable "tfc_vcs_repo_ingress_submodules" {
  type        = bool
  default     = false
  description = "Flag to enable support for VCS submodules in the repository"
}
variable "oidc_provider_arn" {
  type        = string
  description = "The ARN of the OIDC provider to use for federated identity"
}

variable "oidc_provider_client_id_list" {
  type        = list(string)
  description = "The client ID list for the OIDC provider"
}
