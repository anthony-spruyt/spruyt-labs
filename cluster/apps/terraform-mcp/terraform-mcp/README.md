# terraform-mcp - HCP Terraform MCP Server

## Overview

Gives agents read access to TFC workspaces, runs and plan/apply logs, and lets them apply, discard or cancel runs. Our workspaces are VCS-driven, so the `terraform` CLI can't apply them. Served behind the LiteLLM MCP gateway; the only ingress this pod accepts is from LiteLLM.

## Prerequisites

- `TFE_TOKEN` in `app/terraform-mcp-secrets.sops.yaml` is an **owners** team token minted by `tfe_team_token.terraform_mcp` in `infra/terraform/workspace-factory`. The free TFC plan has no custom teams, so no narrower token can apply runs.

## Operations

- Registered in the LiteLLM UI at `http://terraform-mcp.terraform-mcp.svc:8080/mcp`; see [litellm README](../../litellm/README.md#mcp-servers). `ENABLE_TF_OPERATIONS=true` and `--toolsets=all` expose every tool, including deletes and `force_unlock_workspace`. Restrict tools per key or team with LiteLLM access groups, not in this pod.

- **Token rotation** (also needed before it expires): bump `terraform_mcp_token_expired_at` in `infra/terraform/workspace-factory/variables.auto.tfvars`, push, and apply the `workspace-factory` run. Then rewrite the secret from the repo root without printing the token:

  ```bash
  terraform -chdir=infra/terraform/workspace-factory init
  kubectl create secret generic terraform-mcp-secrets \
    --from-literal=TFE_TOKEN="$(terraform -chdir=infra/terraform/workspace-factory output -raw terraform_mcp_tfc_token)" \
    --dry-run=client -o yaml \
    | sops -e --filename-override cluster/apps/terraform-mcp/terraform-mcp/app/terraform-mcp-secrets.sops.yaml /dev/stdin \
    > cluster/apps/terraform-mcp/terraform-mcp/app/terraform-mcp-secrets.sops.yaml
  ```

  Commit, push, and restart the deployment to pick up the new token.

## Troubleshooting

1. **Every TFC tool returns 401**
   - **Cause**: The team token expired or was regenerated outside Terraform.
   - **Fix**: Follow the token rotation steps above.

## References

- [terraform-mcp-server GitHub](https://github.com/hashicorp/terraform-mcp-server)
- [Terraform MCP server docs](https://developer.hashicorp.com/terraform/mcp-server)
