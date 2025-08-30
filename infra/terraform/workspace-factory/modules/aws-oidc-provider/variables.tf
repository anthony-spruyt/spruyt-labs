variable "tfc_hostname" {
  type        = string
  default     = "app.terraform.io"
  description = "The hostname of the Terraform Cloud (TFC) or Terraform Enterprise (TFE) instance to use for workspace integration"
}

variable "tfc_aws_audience" {
  type        = string
  default     = "aws.workload.identity"
  description = "The audience value to use in AWS workload identity tokens for Terraform Cloud"
}

variable "aws_region" {
  type        = string
  default     = "ap-southeast-4" # ap-southeast-2 = Sydney ; ap-southeast-4 = Melbourne
  description = "The AWS region in which to provision all resources"
}
