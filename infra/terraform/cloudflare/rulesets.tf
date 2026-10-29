locals {
  authentik_path = "lower(url_decode(http.request.uri.path))"
  authentik_admin_prefixes = [
    "/if/admin",
    "/api/v3/crypto/",
    "/api/v3/lifecycle/",
    "/api/v3/managed/",
    "/api/v3/oauth2/",
    "/api/v3/propertymappings/",
    "/api/v3/providers/",
    "/api/v3/rbac/",
    "/api/v3/reports/",
    "/api/v3/ssf/",
    "/api/v3/policies/",
    "/api/v3/tasks/",
    "/api/v3/tenants/",
    "/api/v3/schema/",
    "/api/v3/authenticators/admin/",
    "/api/v3/admin/apps/",
    "/api/v3/admin/models/",
    "/api/v3/admin/system/",
    "/api/v3/admin/file/",
  ]

  litellm_host = "litellm.${var.zone_name}"
  litellm_ci_paths = [
    "/v1/messages",
    "/v1/messages/count_tokens",
    "/v1/chat/completions",
    "/health/liveliness",
  ]
  litellm_ci_path_regex = "^(${join("|", local.litellm_ci_paths)})$"

  blog_host                   = var.zone_name
  blog_allowed_bot_categories = ["Search Engine Crawler", "Feed Fetcher", "Page Preview"]

  github_webhook_hosts = ["flux-webhook.${var.zone_name}", "hooks.${var.zone_name}", "n8n.${var.zone_name}"]

  authentik_admin_expression = format(
    "lower(http.host) eq \"auth.%s\" and not ip.src in {%s} and (%s in {\"/api/v3\" \"/api/v3/\"} or %s)",
    var.zone_name,
    var.home_ip,
    local.authentik_path,
    join(" or ", [for prefix in local.authentik_admin_prefixes : format("starts_with(%s, \"%s\")", local.authentik_path, prefix)]),
  )

  challenged_asns = [
    8075,
    16509,
    14618,
    15169,
    396982,
    14061,
    24940,
    16276,
    63949,
    31898,
    20473,
    45102,
    132203,
  ]
}

resource "cloudflare_ruleset" "firewall_custom" {
  zone_id = local.zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  rules = [
    {
      ref         = "aa33d28c23da43398c537f031a25a261"
      description = "Allow GitHub Webhooks"
      expression = format(
        "(ip.src in {9.234.106.48/28 9.234.98.160/28 9.234.98.176/28 192.30.252.0/22 185.199.108.0/22 140.82.112.0/20 143.55.64.0/20 2a0a:a440::/29 2606:50c0::/32}) and lower(http.host) in {%s}",
        join(" ", [for host in local.github_webhook_hosts : format("\"%s\"", host)]),
      )
      action = "skip"
      action_parameters = {
        ruleset  = "current"
        phases   = ["http_ratelimit", "http_request_firewall_managed", "http_request_sbfm"]
        products = ["zoneLockdown", "uaBlock", "bic", "hot", "securityLevel", "rateLimit", "waf"]
      }
      logging = {
        enabled = true
      }
      enabled = true
    },
    {
      ref         = "a2f6b0f5d2254d04a8665581a8dd234b"
      description = "Block non-AU traffic, bots, and non-API LiteLLM paths"
      expression = format(
        "(ip.src.country ne \"AU\" and lower(http.host) ne \"%[1]s\" and lower(http.host) ne \"%[3]s\") or (cf.client.bot and not (lower(http.host) eq \"%[3]s\" and (cf.verified_bot_category in {%[4]s} or (cf.verified_bot_category eq \"Security\" and http.user_agent contains \"Google-InspectionTool\")))) or (lower(http.host) eq \"%[1]s\" and not lower(url_decode(http.request.uri.path)) in {%[2]s})",
        local.litellm_host,
        join(" ", [for path in local.litellm_ci_paths : format("\"%s\"", path)]),
        local.blog_host,
        join(" ", [for category in local.blog_allowed_bot_categories : format("\"%s\"", category)]),
      )
      action  = "block"
      enabled = true
    },
    {
      # This ref links the rule to the dashboard's AI Crawl Control page.
      ref         = "[CF AI Audit]"
      description = "AI Crawl Control - Block AI bots by User Agent"
      expression  = "(http.request.uri.path ne \"/robots.txt\") and ((http.user_agent contains \"archive.org_bot\") or (http.user_agent contains \"Arquivo-web-crawler\") or (http.user_agent contains \"ChatGPT-User\") or (http.user_agent contains \"DuckAssistBot\") or (http.user_agent contains \"Manus-User\") or (http.user_agent contains \"meta-externalfetcher\") or (http.user_agent contains \"MistralAI-User\") or (http.user_agent contains \"OAI-SearchBot\") or (http.user_agent contains \"Perplexity-User\") or (http.user_agent contains \"PerplexityBot\") or (http.user_agent contains \"ProRataInc\") or (http.user_agent contains \"Terracotta\"))"
      action      = "block"
      enabled     = true
    },
    {
      ref         = "block-authentik-admin"
      description = "Block Authentik admin paths outside home"
      expression  = local.authentik_admin_expression
      action      = "block"
      enabled     = true
    },
    {
      ref         = "challenge-cloud-asns"
      description = "Managed challenge for cloud and hosting networks"
      expression = format(
        "(ip.src.asnum in {%s}) and (lower(http.host) ne \"%s\") and (lower(http.host) ne \"%s\")",
        join(" ", local.challenged_asns),
        local.litellm_host,
        local.blog_host,
      )
      action  = "managed_challenge"
      enabled = true
    },
  ]
}

resource "cloudflare_ruleset" "rate_limit" {
  zone_id = local.zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [
    {
      ref         = "d24c0170ae8448858868d878ca1a911e"
      description = "Rate limit authentication pages"
      expression  = "(http.request.uri.path contains \"login\" or http.request.uri.path contains \"signin\")"
      action      = "block"
      ratelimit = {
        characteristics     = ["ip.src", "cf.colo.id"]
        period              = 10
        requests_per_period = 3
        mitigation_timeout  = 10
      }
      enabled = true
    },
  ]
}

resource "cloudflare_ruleset" "cache" {
  zone_id = local.zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      ref         = "f40ed470cf824ebf9978a56957c2fb16"
      description = "Bypass cache for everything [Template]"
      expression  = "true"
      action      = "set_cache_settings"
      action_parameters = {
        cache = false
      }
      enabled = true
    },
    {
      ref         = "cache-blog-respect-origin"
      description = "Cache the blog host per origin headers"
      expression  = format("(lower(http.host) eq \"%s\")", local.blog_host)
      action      = "set_cache_settings"
      action_parameters = {
        cache = true
        edge_ttl = {
          mode = "respect_origin"
          status_code_ttl = [
            {
              status_code_range = { from = 500, to = 599 }
              value             = -1
            },
          ]
        }
      }
      enabled = true
    },
  ]
}

resource "cloudflare_ruleset" "redirect" {
  zone_id = local.zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [
    {
      ref         = "redirect-www-to-apex"
      description = "Redirect www to the apex"
      expression  = format("(lower(http.host) eq \"www.%s\")", var.zone_name)
      action      = "redirect"
      action_parameters = {
        from_value = {
          status_code = 301
          target_url = {
            expression = format("concat(\"https://%s\", http.request.uri.path)", local.blog_host)
          }
          preserve_query_string = true
        }
      }
      enabled = true
    },
  ]
}
