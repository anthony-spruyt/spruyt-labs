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

variable "aws_region" {
  type        = string
  description = "AWS region for resources (override via Terraform Cloud variable set)"
  default     = "ap-southeast-4" # ap-southeast-2 = Sydney ; ap-southeast-4 = Melbourne
}

variable "aws_replica_region" {
  type        = string
  description = "AWS region for cross-region replication destination bucket (override via Terraform Cloud variable set)"
  default     = "ap-southeast-2" # ap-southeast-2 = Sydney ; ap-southeast-4 = Melbourne
}
