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
  description = "The name of the Terraform Cloud workspace to create"
}

variable "tfc_working_directory" {
  type        = string
  description = "The working directory within the VCS repository for the Terraform Cloud workspace"
}

variable "tfc_trigger_pattern" {
  type        = string
  description = "The glob pattern used to match VCS webhook triggers for this workspace"
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

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  ephemeral   = true
  description = "Cloudflare API token the workspace uses to manage Cloudflare"
}

variable "cloudflare_account_id" {
  type        = string
  sensitive   = true
  ephemeral   = true
  description = "Cloudflare account ID"
}

variable "cloudflare_zone_name" {
  type        = string
  sensitive   = true
  ephemeral   = true
  description = "Cloudflare zone (apex domain) name"
}

variable "cloudflare_dns_verification" {
  type        = map(string)
  sensitive   = true
  ephemeral   = true
  description = "Per-domain DNS verification tokens and IDs, passed through to the workspace's dns_verification variable"
}

variable "tfc_variables_version" {
  type        = number
  description = "Bump to push new values of the write-only Cloudflare variables to the workspace"
}
