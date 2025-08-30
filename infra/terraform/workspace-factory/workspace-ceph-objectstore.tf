
locals {
  ceph_bucket_pattern = "arn:aws:s3:::spruyt-labs-${var.aws_account_id}-prod-ceph-*"
}

data "aws_iam_policy_document" "ceph_objectstore_aws_iam_policy" {
  version = "2012-10-17"
  statement {
    sid    = "CephObjectStoreTerraformAccess"
    effect = "Allow"
    actions = [
      "s3:*",
    ]
    resources = [
      local.ceph_bucket_pattern,
      "${local.ceph_bucket_pattern}/*"
    ]
  }
}

module "ceph-objectstore" {
  source                  = "./modules/aws-workspace"
  tfc_organization_name   = var.tfc_organization_name
  tfc_project_name        = var.tfc_project_name
  tfc_workspace_name      = var.ceph_objectstore_tfc_workspace_name
  aws_iam_policy_document = data.aws_iam_policy_document.ceph_objectstore_aws_iam_policy.json
}
