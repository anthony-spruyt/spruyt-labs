output "tunnel_id" {
  value       = cloudflare_zero_trust_tunnel_cloudflared.this.id
  description = "ID of the spruyt-labs-01 Cloudflare Tunnel"
}

output "tunnel_hostnames" {
  value       = values(local.tunnel_hostnames)
  description = "Public hostnames routed through the tunnel"
}
