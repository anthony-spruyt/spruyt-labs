variable "project" {
  type        = string
  description = "Project tag and name prefix (configured in Terraform Cloud variable sets)"
}

variable "environment" {
  type        = string
  description = "Environment tag (configured in Terraform Cloud variable sets)"
}
