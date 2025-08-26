data "aws_caller_identity" "current" {}

locals {
  # Format: {project}-{accountid}-{environment}-ceph-objectstore
  bucket_name = lower("${var.project}-${data.aws_caller_identity.current.account_id}-${var.environment}-ceph-objectstore")

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = "anthony"
    ManagedBy   = "terraform"
  }
}

# Core bucket
resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name
  tags   = local.common_tags
}

# Enforce bucket owner for all objects (no ACLs)
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Block all public access, always
resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Default server-side encryption (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle: transition to STANDARD_IA after 30 days
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "transition-to-ia-30d"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }

  depends_on = [
    aws_s3_bucket_server_side_encryption_configuration.this
  ]
}
