variable "aws_region" {
  type        = string
  description = "AWS region for resources"
  default     = "ap-southeast-2" # Sydney
}

provider "aws" {
  region = var.aws_region
}
