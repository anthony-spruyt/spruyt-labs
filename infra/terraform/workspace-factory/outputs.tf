output "terraform_mcp_tfc_token" {
  value       = tfe_team_token.terraform_mcp.token
  sensitive   = true
  description = "TFC owners team token for the in-cluster terraform-mcp server"
}
