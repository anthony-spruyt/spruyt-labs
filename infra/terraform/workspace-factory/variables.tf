variable "tfc_hostname" {
  type        = string
  default     = "app.terraform.io"
  description = "The hostname of the TFC or TFE instance you'd like to use with AWS"
}

variable "tfc_organization_name" {
  type        = string
  description = "The name of your Terraform Cloud organization"
}

variable "tfc_project_name" {
  type        = string
  description = "The project under which a workspace will be created"
}

variable "ceph_objectstore_tfc_workspace_name" {
  type        = string
  description = "The name of the ceph objectstore workspace to create and connect to AWS"
}

variable "velero_backup_tfc_workspace_name" {
  type        = string
  description = "The name of the Velero workspace to create and connect to AWS"
}

variable "aws_region" {
  type        = string
  default     = "ap-southeast-4" # ap-southeast-2 = Sydney ; ap-southeast-4 = Melbourne
  description = "AWS region for resources"
}

variable "aws_account_id" {
  type        = string
  description = "The AWS account ID"
}
