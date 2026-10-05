data "tfe_team" "owners" {
  name         = "owners"
  organization = var.tfc_organization_name
}

resource "tfe_team_token" "terraform_mcp" {
  team_id     = data.tfe_team.owners.id
  description = "terraform-mcp"
  expired_at  = var.terraform_mcp_token_expired_at
}
