terraform {
  required_version = "~> 1.13"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.25"
    }
  }

  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "spruyt-labs"
    workspaces {
      name = "cloudflare"
    }
  }
}
