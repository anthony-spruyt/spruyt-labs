# output "velero_backup_bucket" {
#   description = "The name of the S3 bucket for Velero backups"
#   value       = aws_s3_bucket.velero.id
# }
#
# output "velero_iam_user" {
#   description = "The IAM user for Velero S3 access"
#   value       = aws_iam_user.velero.name
# }
#
# output "velero_iam_access_key_id" {
#   description = "The access key ID for the Velero IAM user"
#   value       = aws_iam_access_key.velero.id
# }
#
# output "velero_iam_secret_access_key" {
#   description = "The secret access key for the Velero IAM user"
#   value       = aws_iam_access_key.velero.secret
#   sensitive   = true
# }
