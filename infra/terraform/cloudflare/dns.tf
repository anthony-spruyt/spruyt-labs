locals {
  # Brevo sender domains ("@" is the zone apex) => record TTL.
  brevo_senders = {
    "@"         = 3600
    auth        = 1
    ha          = 1
    n8n         = 3600
    vaultwarden = 1
  }

  brevo_records = merge([
    for sub, ttl in local.brevo_senders : {
      "brevo-dkim1-${sub}" = {
        type    = "CNAME"
        name    = sub == "@" ? "brevo1._domainkey" : "brevo1._domainkey.${sub}"
        content = "b1.${replace(sub == "@" ? var.zone_name : "${sub}.${var.zone_name}", ".", "-")}.dkim.brevo.com"
        ttl     = ttl
      }
      "brevo-dkim2-${sub}" = {
        type    = "CNAME"
        name    = sub == "@" ? "brevo2._domainkey" : "brevo2._domainkey.${sub}"
        content = "b2.${replace(sub == "@" ? var.zone_name : "${sub}.${var.zone_name}", ".", "-")}.dkim.brevo.com"
        ttl     = ttl
      }
      "brevo-code-${sub}" = {
        type    = "TXT"
        name    = sub
        content = "\"brevo-code:${var.dns_verification.brevo_code}\""
        ttl     = ttl
      }
    }
  ]...)

  static_records = {
    ha = {
      type    = "CNAME"
      name    = "ha"
      content = "${var.dns_verification.nabu_casa_remote_ui_id}.ui.nabu.casa"
      ttl     = 1
    }
    ha-acme-challenge = {
      type    = "CNAME"
      name    = "_acme-challenge.ha"
      content = "_acme-challenge.${var.dns_verification.nabu_casa_remote_ui_id}.ui.nabu.casa"
      ttl     = 1
    }
    dmarc = {
      type    = "TXT"
      name    = "_dmarc"
      content = "\"v=DMARC1; p=reject; rua=mailto:${var.dns_verification.dmarc_cloudflare_rua}@dmarc-reports.cloudflare.net,mailto:rua@dmarc.brevo.com; pct=100\""
      ttl     = 1
    }
    spf-apex = {
      type    = "TXT"
      name    = "@"
      content = "\"v=spf1 include:_spf.mx.cloudflare.net ~all\""
      ttl     = 1
    }
    spf-homeassistant = {
      type    = "TXT"
      name    = "homeassistant"
      content = "\"v=spf1 include:spf.brevo.com ~all\""
      ttl     = 1
    }
    spf-vaultwarden = {
      type    = "TXT"
      name    = "vaultwarden"
      content = "\"v=spf1 include:spf.brevo.com ~all\""
      ttl     = 1
    }
    verify-google = {
      type    = "TXT"
      name    = "@"
      content = "\"google-site-verification=${var.dns_verification.google_site}\""
      ttl     = 3600
    }
    verify-microsoft = {
      type    = "TXT"
      name    = "@"
      content = "\"MS=${var.dns_verification.microsoft}\""
      ttl     = 3600
    }
    verify-twilio = {
      type    = "TXT"
      name    = "_twilio"
      content = "\"twilio-domain-verification=${var.dns_verification.twilio}\""
      ttl     = 1
    }
  }

  dns_records = {
    for k, r in merge(local.static_records, local.brevo_records) : k => merge(r, {
      fqdn = r.name == "@" ? var.zone_name : "${r.name}.${var.zone_name}"
    })
  }
}

# Email Routing MX and DKIM records are read-only (owned by Email Routing) and not managed here.
resource "cloudflare_dns_record" "this" {
  for_each = local.dns_records

  zone_id = local.zone_id
  name    = each.value.fqdn
  type    = each.value.type
  content = each.value.content
  proxied = false
  ttl     = each.value.ttl
}
