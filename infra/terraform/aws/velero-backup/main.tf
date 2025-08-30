data "aws_caller_identity" "current" {}

locals {
  # Format: {project}-{accountid}-{environment}-ceph-objectstore
  bucket_name = lower("${var.project}-${data.aws_caller_identity.current.account_id}-${var.environment}-velero-backup")

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket" "velero" {
  bucket        = local.bucket_name
  force_destroy = false
  tags          = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_user" "velero" {
  name = "velero-backup"
  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_iam_access_key" "velero" {
  user = aws_iam_user.velero.name
}

data "aws_iam_policy_document" "velero" {
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [aws_s3_bucket.velero.arn]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    resources = ["${aws_s3_bucket.velero.arn}/*"]
  }
}

resource "aws_iam_policy" "velero" {
  name   = "velero-backup"
  policy = data.aws_iam_policy_document.velero.json
  tags   = local.common_tags
}

resource "aws_iam_user_policy_attachment" "velero" {
  user       = aws_iam_user.velero.name
  policy_arn = aws_iam_policy.velero.arn
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket                  = aws_s3_bucket.velero.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
