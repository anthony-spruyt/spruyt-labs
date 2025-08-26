############################################################
# TFC OIDC role with anchored S3 bucket & alias‑driven KMS scoping
############################################################
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.10"
    }
  }
}

locals {
  # Anchored pattern so future Ceph buckets under this namespace are included
  ceph_bucket_pattern = "arn:aws:s3:::spruyt-labs-${var.aws_account_id}-prod-ceph-*"
}

# Resolve KMS ARNs from aliases instead of hardcoding IDs
# Update aliases to match those in your AWS KMS console
data "terraform_remote_state" "buckets" {
  backend = "remote"
  config = {
    organization = var.tfc_org_name
    workspaces = {
      name = "aws-ceph-objectstore"
    }
  }
}

data "aws_kms_key" "ceph_main" {
  key_id = data.terraform_remote_state.buckets.outputs.main_kms_alias_name
}

data "aws_kms_key" "ceph_logs" {
  key_id = data.terraform_remote_state.buckets.outputs.logs_kms_alias_name
}

locals {
  ceph_kms_keys = [
    data.aws_kms_key.ceph_main.arn,
    data.aws_kms_key.ceph_logs.arn
  ]
}

# OIDC trust policy for Terraform Cloud
data "aws_iam_policy_document" "tfc_oidc_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type = "Federated"
      identifiers = [
        "arn:aws:iam::${var.aws_account_id}:oidc-provider/app.terraform.io"
      ]
    }

    # Restrict to your org's workspaces and run phases
    condition {
      test     = "StringEquals"
      variable = "app.terraform.io:aud"
      values   = ["aws.workload.identity"]
    }

    condition {
      test     = "StringLike"
      variable = "app.terraform.io:sub"
      values = [
        "organization:${var.tfc_org_name}:project:*:workspace:*:run_phase:*"
      ]
    }
  }
}

resource "aws_iam_role" "tfc_oidc" {
  name               = "tfc-oidc-terraform"
  assume_role_policy = data.aws_iam_policy_document.tfc_oidc_trust.json
}

# Permissions policy
data "aws_iam_policy_document" "tfc_oidc_policy" {
  # Bucket‑level permissions
  statement {
    sid = "CephListBuckets"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      local.ceph_bucket_pattern,
      "${local.ceph_bucket_pattern}/*"
    ]
  }

  # Object‑level permissions for main data bucket
  statement {
    sid = "CephMainBucketObjects"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:GetObjectTagging",
      "s3:PutObjectTagging"
    ]
    resources = [
      "arn:aws:s3:::spruyt-labs-${var.aws_account_id}-prod-ceph-objectstore/*"
    ]
  }

  # Object‑level permissions for logs bucket
  statement {
    sid = "CephLogsBucketObjects"
    actions = [
      "s3:PutObject"
    ]
    resources = [
      "arn:aws:s3:::spruyt-labs-${var.aws_account_id}-prod-ceph-objectstore-logs/*"
    ]
  }

  # KMS for SSE‑KMS encryption/decryption — now alias‑driven
  statement {
    sid = "CephKMSAccess"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = local.ceph_kms_keys
  }
}

resource "aws_iam_role_policy" "tfc_oidc_inline" {
  name   = "tfc-oidc-inline"
  role   = aws_iam_role.tfc_oidc.id
  policy = data.aws_iam_policy_document.tfc_oidc_policy.json
}

output "tfc_oidc_role_arn" {
  value = aws_iam_role.tfc_oidc.arn
}
