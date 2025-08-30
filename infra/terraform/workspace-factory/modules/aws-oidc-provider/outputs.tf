output "aws_oidc_provider_arn" {
  description = "The ARN of the OIDC provider"
  value       = aws_iam_openid_connect_provider.tfc_provider.arn
}

output "aws_oidc_provider_url" {
  description = "The URL of the OIDC provider"
  value       = aws_iam_openid_connect_provider.tfc_provider.url
}

output "aws_oidc_provider_client_id_list" {
  description = "The client ID list of the OIDC provider"
  value       = aws_iam_openid_connect_provider.tfc_provider.client_id_list
}
