provider "aws" {
  region = var.aws_region
}

provider "tfe" {
  hostname = var.tfc_hostname
}
