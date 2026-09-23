locals {
  zone_settings = {
    "0rtt"                   = "off"
    always_online            = "off"
    always_use_https         = "on"
    automatic_https_rewrites = "on"
    browser_check            = "on"
    email_obfuscation        = "on"
    hotlink_protection       = "on"
    http3                    = "off"
    ipv6                     = "on"
    min_tls_version          = "1.3"
    opportunistic_encryption = "on"
    security_level           = "medium"
    ssl                      = "full"
    tls_1_3                  = "on"
    websockets               = "on"
  }
}

resource "cloudflare_zone_setting" "this" {
  for_each = local.zone_settings

  zone_id    = local.zone_id
  setting_id = each.key
  value      = each.value
}
