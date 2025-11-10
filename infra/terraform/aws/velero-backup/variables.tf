variable "project" {
  type        = string
  description = "Project tag and name prefix (configured in Terraform Cloud variable sets)"
}

variable "environment" {
  type        = string
  description = "Environment tag (configured in Terraform Cloud variable sets)"
}

variable "expiration" {
  type        = number
  description = "Number of days to retain non-current object versions in the Velero S3 bucket"
  default     = 30
}
