output "bucket_name" {
  value = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "log_bucket_name" {
  value = aws_s3_bucket.log_bucket.bucket
}

output "log_bucket_arn" {
  value = aws_s3_bucket.log_bucket.arn
}

output "main_kms_alias_name" {
  value = aws_kms_alias.this_alias.name
}

output "logs_kms_alias_name" {
  value = aws_kms_alias.log_bucket_alias.name
}
