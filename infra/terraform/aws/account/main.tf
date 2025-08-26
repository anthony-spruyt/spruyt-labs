module "iam" {
  source         = "./modules/iam"
  tfc_org_name   = var.tfc_org_name
  aws_account_id = var.aws_account_id
}

# Output the role ARN so other workspaces can consume it
output "tfc_oidc_role_arn" {
  value = module.iam.tfc_oidc_role_arn
}
