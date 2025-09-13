terraform {
  required_version = "~> 1.13"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.13"
    }
  }

  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "spruyt-labs"
    workspaces {
      name = "velero-backup"
    }
  }
}
