resource "cloudflare_ruleset" "firewall_custom" {
  zone_id = local.zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  rules = [
    {
      ref         = "aa33d28c23da43398c537f031a25a261"
      description = "Allow GitHub Webhooks"
      expression  = "(ip.src in {192.30.252.0/22 185.199.108.0/22 140.82.112.0/20 143.55.64.0/20})"
      action      = "skip"
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
      description = "Allow Australia Only"
      expression  = "(ip.src.country ne \"AU\")"
      action      = "block"
      enabled     = true
    },
    {
      ref         = "f77da3210fe8432992c9148f64589d43"
      description = "Block bots"
      expression  = "(cf.client.bot)"
      action      = "block"
      enabled     = true
    },
    {
      # This ref links the rule to the dashboard's AI Crawl Control page.
      ref         = "[CF AI Audit]"
      description = "AI Crawl Control - Block AI bots by User Agent"
      expression  = "(http.request.uri.path ne \"/robots.txt\") and ((http.user_agent contains \"Applebot\") or (http.user_agent contains \"archive.org_bot\") or (http.user_agent contains \"Arquivo-web-crawler\") or (http.user_agent contains \"bingbot\") or (http.user_agent contains \"ChatGPT-User\") or (http.user_agent contains \"DuckAssistBot\") or (http.user_agent contains \"Googlebot\") or (http.user_agent contains \"Manus-User\") or (http.user_agent contains \"meta-externalfetcher\") or (http.user_agent contains \"MistralAI-User\") or (http.user_agent contains \"OAI-SearchBot\") or (http.user_agent contains \"Perplexity-User\") or (http.user_agent contains \"PerplexityBot\") or (http.user_agent contains \"ProRataInc\") or (http.user_agent contains \"Terracotta\"))"
      action      = "block"
      enabled     = true
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
  ]
}
