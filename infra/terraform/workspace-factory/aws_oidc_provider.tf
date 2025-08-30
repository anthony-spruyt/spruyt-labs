module "aws_oidc_provider" {
  source           = "./modules/aws-oidc-provider"
  tfc_hostname     = var.tfc_hostname
  tfc_aws_audience = var.tfc_aws_audience
  aws_region       = var.aws_region
}
