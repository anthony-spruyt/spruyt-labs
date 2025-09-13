terraform {
  required_version = "~> 1.13"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.13"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.68"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1"
    }
  }

  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "spruyt-labs"
    workspaces {
      name = "workspace-factory"
    }
  }
}
