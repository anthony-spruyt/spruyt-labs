# One-shot adoption of the existing clickops resources. Delete this file after the first apply.

data "cloudflare_zero_trust_tunnel_cloudflareds" "import" {
  account_id = var.cloudflare_account_id
  name       = "spruyt-labs-01"
  is_deleted = false
}

data "cloudflare_dns_records" "import" {
  zone_id   = local.zone_id
  max_items = 500
}

data "cloudflare_rulesets" "import" {
  zone_id = local.zone_id
}

locals {
  import_tunnel_id = one(data.cloudflare_zero_trust_tunnel_cloudflareds.import.result).id

  import_dns_record_ids = {
    for r in data.cloudflare_dns_records.import.result : "${r.type}/${r.name}/${r.content}" => r.id
  }

  import_ruleset_ids = {
    for r in data.cloudflare_rulesets.import.rulesets : r.phase => r.id if r.kind == "zone"
  }
}

import {
  to = cloudflare_zero_trust_tunnel_cloudflared.this
  id = "${var.cloudflare_account_id}/${local.import_tunnel_id}"
}

import {
  to = cloudflare_zero_trust_tunnel_cloudflared_config.this
  id = "${var.cloudflare_account_id}/${local.import_tunnel_id}"
}

import {
  for_each = local.tunnel_hostnames
  to       = cloudflare_dns_record.tunnel[each.key]
  id       = "${local.zone_id}/${local.import_dns_record_ids["CNAME/${each.value}/${local.import_tunnel_id}.cfargotunnel.com"]}"
}

import {
  for_each = local.dns_records
  to       = cloudflare_dns_record.this[each.key]
  id       = "${local.zone_id}/${local.import_dns_record_ids["${each.value.type}/${each.value.fqdn}/${each.value.content}"]}"
}

import {
  to = cloudflare_ruleset.firewall_custom
  id = "zones/${local.zone_id}/${local.import_ruleset_ids["http_request_firewall_custom"]}"
}

import {
  to = cloudflare_ruleset.rate_limit
  id = "zones/${local.zone_id}/${local.import_ruleset_ids["http_ratelimit"]}"
}

import {
  to = cloudflare_ruleset.cache
  id = "zones/${local.zone_id}/${local.import_ruleset_ids["http_request_cache_settings"]}"
}

import {
  for_each = local.zone_settings
  to       = cloudflare_zone_setting.this[each.key]
  id       = "${local.zone_id}/${each.key}"
}
