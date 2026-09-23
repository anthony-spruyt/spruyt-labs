output "tunnel_id" {
  value       = cloudflare_zero_trust_tunnel_cloudflared.this.id
  description = "ID of the spruyt-labs-01 Cloudflare Tunnel"
}

output "tunnel_subdomains" {
  value       = keys(local.tunnel_hostnames)
  description = "Subdomains routed through the tunnel (\"@\" is the zone apex)"
}
