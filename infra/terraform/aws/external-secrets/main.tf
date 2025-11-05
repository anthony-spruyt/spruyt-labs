# data "aws_caller_identity" "current" {}

locals {
  # Format: {project}-{accountid}-{environment}-cnpg-backup
  # secret_name = lower("${var.project}-${data.aws_caller_identity.current.account_id}-${var.environment}-external-secrets")

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_ssm_parameter" "secret_a" {
  name        = "/production/database/password/master"
  description = "The parameter description"
  type        = "SecureString"
  value       = "dummy"
  tags        = local.common_tags
}

# resource "aws_secretsmanager_secret" "external_secrets" {
#   name   = local.secret_name
#   region = var.aws_region
#   tags   = local.common_tags
# }

resource "aws_iam_user" "external_secrets" {
  name = "external-secrets"
  tags = local.common_tags
}

# data "aws_iam_policy_document" "external_secrets" {
#   statement {
#     actions = [
#       "secretsmanager:*"
#     ]
#     resources = [aws_secretsmanager_secret.external_secrets.arn]
#   }
# }
#
# resource "aws_iam_policy" "external_secrets" {
#   name   = "external_secrets"
#   policy = data.aws_iam_policy_document.external_secrets.json
#   tags   = local.common_tags
# }
#
# resource "aws_iam_user_policy_attachment" "external_secrets" {
#   user       = aws_iam_user.external_secrets.name
#   policy_arn = aws_iam_policy.external_secrets.arn
# }
