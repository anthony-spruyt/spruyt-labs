terraform {
  required_version = "~> 1.13"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.10"
    }
  }

  backend "remote" {
    organization = "spruyt-labs"
    workspaces {
      name = "aws-account"
    }
  }
}
