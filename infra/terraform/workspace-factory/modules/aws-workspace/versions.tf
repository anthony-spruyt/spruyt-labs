terraform {
  required_version = "~> 1.13"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.19"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.74"
    }
  }
}
