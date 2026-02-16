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
