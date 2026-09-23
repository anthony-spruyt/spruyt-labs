locals {
  traefik_service = "https://traefik.traefik.svc.cluster.local"

  # Ingress is matched top-down. "@" is the zone apex.
  tunnel_routes = [
    {
      subdomain      = "auth"
      service        = local.traefik_service
      origin_request = { http2_origin = true, origin_server_name = "auth.${var.zone_name}" }
    },
    {
      subdomain      = "code"
      service        = local.traefik_service
      origin_request = { http2_origin = true, origin_server_name = "code.${var.zone_name}" }
    },
    {
      subdomain      = "flux-webhook"
      service        = "http://webhook-receiver.flux-system.svc.cluster.local"
      origin_request = {}
    },
    {
      subdomain      = "foundry"
      service        = local.traefik_service
      origin_request = { http2_origin = true, origin_server_name = "foundry.${var.zone_name}" }
    },
    {
      subdomain      = "n8n"
      service        = local.traefik_service
      origin_request = { http2_origin = true, origin_server_name = "n8n.${var.zone_name}" }
    },
    {
      subdomain      = "vaultwarden"
      service        = local.traefik_service
      origin_request = { http2_origin = true, origin_server_name = "vaultwarden.${var.zone_name}", no_tls_verify = false, tls_timeout = 10 }
    },
    {
      subdomain      = "www"
      service        = local.traefik_service
      origin_request = { http2_origin = true, no_tls_verify = true }
    },
    {
      subdomain      = "@"
      service        = local.traefik_service
      origin_request = { http2_origin = true, no_tls_verify = true }
    },
  ]

  tunnel_hostnames = {
    for r in local.tunnel_routes : r.subdomain => r.subdomain == "@" ? var.zone_name : "${r.subdomain}.${var.zone_name}"
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id = var.cloudflare_account_id
  name       = "spruyt-labs-01"
  config_src = "cloudflare"

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [tunnel_secret]
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id

  config = {
    ingress = concat(
      [
        for r in local.tunnel_routes : {
          hostname       = local.tunnel_hostnames[r.subdomain]
          service        = r.service
          origin_request = r.origin_request
        }
      ],
      [{ service = "http_status:404" }],
    )
  }

  lifecycle {
    prevent_destroy = true
  }
}

# The dashboard auto-creates these CNAMEs when a route is added; the API does not.
resource "cloudflare_dns_record" "tunnel" {
  for_each = local.tunnel_hostnames

  zone_id = local.zone_id
  name    = each.value
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}
