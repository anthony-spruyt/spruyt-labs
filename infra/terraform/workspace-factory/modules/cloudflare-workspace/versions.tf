terraform {
  required_version = "~> 1.13"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.81"
    }
  }
}
