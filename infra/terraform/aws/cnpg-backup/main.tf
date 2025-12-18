data "aws_caller_identity" "current" {}

locals {
  # Format: {project}-{accountid}-{environment}-cnpg-backup
  bucket_name         = lower("${var.project}-${data.aws_caller_identity.current.account_id}-${var.environment}-cnpg-backup")
  replica_bucket_name = lower("${var.project}-${data.aws_caller_identity.current.account_id}-${var.environment}-cnpg-backup-replica")

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket" "cnpg" {
  bucket        = local.bucket_name
  force_destroy = false
  tags          = local.common_tags
}

resource "aws_s3_bucket" "cnpg_replica" {
  bucket        = local.replica_bucket_name
  region        = var.aws_replica_region
  force_destroy = false
  tags          = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cnpg" {
  bucket = aws_s3_bucket.cnpg.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cnpg_replica" {
  bucket = aws_s3_bucket.cnpg_replica.id
  region = var.aws_replica_region

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_user" "cnpg" {
  name = "cnpg-backup"
  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "cnpg" {
  bucket = aws_s3_bucket.cnpg.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "cnpg_replica" {
  bucket = aws_s3_bucket.cnpg_replica.id
  region = var.aws_replica_region

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cnpg" {
  bucket = aws_s3_bucket.cnpg.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.expiration
    }
  }
}

resource "aws_s3_bucket_replication_configuration" "cnpg" {
  depends_on = [aws_s3_bucket_versioning.cnpg_replica]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.cnpg.id

  rule {
    id       = "cnpg-backup-replication"
    status   = "Enabled"
    priority = 1

    destination {
      bucket        = aws_s3_bucket.cnpg_replica.arn
      storage_class = "DEEP_ARCHIVE"
    }
  }
}

data "aws_iam_policy_document" "cnpg" {
  statement {
    actions = [
      "s3:ListBucket"
    ]
    resources = [aws_s3_bucket.cnpg.arn]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    resources = ["${aws_s3_bucket.cnpg.arn}/*"]
  }

  statement {
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "cnpg" {
  name   = "cnpg-backup"
  policy = data.aws_iam_policy_document.cnpg.json
  tags   = local.common_tags
}

resource "aws_iam_user_policy_attachment" "cnpg" {
  user       = aws_iam_user.cnpg.name
  policy_arn = aws_iam_policy.cnpg.arn
}

# IAM role for S3 replication
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "replication" {
  name               = "cnpg-backup-replication-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "replication" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]

    resources = [aws_s3_bucket.cnpg.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]

    resources = ["${aws_s3_bucket.cnpg.arn}/*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]

    resources = ["${aws_s3_bucket.cnpg_replica.arn}/*"]
  }
}

resource "aws_iam_policy" "replication" {
  name   = "cnpg-backup-replication"
  policy = data.aws_iam_policy_document.replication.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "replication" {
  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
}

resource "aws_s3_bucket_public_access_block" "cnpg" {
  bucket                  = aws_s3_bucket.cnpg.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "cnpg_replica" {
  bucket                  = aws_s3_bucket.cnpg_replica.id
  region                  = var.aws_replica_region
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
