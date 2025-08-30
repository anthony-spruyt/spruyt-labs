variable "aws_region" {
  type        = string
  description = "AWS region for resources"
  default     = "ap-southeast-4" # ap-southeast-2 = Sydney ; ap-southeast-4 = Melbourne
}

provider "aws" {
  region = var.aws_region
}
