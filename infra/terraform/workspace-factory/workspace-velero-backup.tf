
locals {
  velero_bucket_pattern = "arn:aws:s3:::spruyt-labs-${var.aws_account_id}-prod-velero-*"
}

data "aws_iam_policy_document" "velero_aws_iam_policy" {
  version = "2012-10-17"
  statement {
    sid    = "VeleroS3TerraformAccess"
    effect = "Allow"
    actions = [
      "s3:*",
    ]
    resources = [
      local.velero_bucket_pattern,
      "${local.velero_bucket_pattern}/*"
    ]
  }
}

module "velero-backup" {
  source                  = "./modules/aws-workspace"
  tfc_organization_name   = var.tfc_organization_name
  tfc_project_name        = var.tfc_project_name
  tfc_workspace_name      = var.velero_backup_tfc_workspace_name
  aws_iam_policy_document = data.aws_iam_policy_document.velero_aws_iam_policy.json
}
