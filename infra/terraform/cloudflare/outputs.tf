output "tunnel_id" {
  value       = cloudflare_zero_trust_tunnel_cloudflared.this.id
  description = "ID of the spruyt-labs-01 Cloudflare Tunnel"
}

output "tunnel_subdomains" {
  value       = keys(local.tunnel_hostnames)
  description = "Subdomains routed through the tunnel (\"@\" is the zone apex)"
}

output "litellm_ci_access_client_id" {
  value       = cloudflare_zero_trust_access_service_token.litellm_ci.client_id
  description = "Client ID of the Access service token for CI (sent as CF-Access-Client-Id)"
}

output "litellm_ci_access_client_secret" {
  value       = cloudflare_zero_trust_access_service_token.litellm_ci.client_secret
  sensitive   = true
  description = "Client secret of the Access service token for CI (sent as CF-Access-Client-Secret)"
}
