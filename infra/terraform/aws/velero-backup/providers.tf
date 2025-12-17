# AWS provider configuration leverages Terraform Cloud Workload Identity for authentication.
# Ensure TFC_AWS_PROVIDER_AUTH, TFC_AWS_RUN_ROLE_ARN, and TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE are set via Variable Sets.
provider "aws" {
  region = var.aws_region
}
