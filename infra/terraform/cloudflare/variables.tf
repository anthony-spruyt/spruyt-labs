variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID (set on the TFC workspace by workspace-factory)"
}

variable "zone_name" {
  type        = string
  description = "Cloudflare zone (apex domain) name (set on the TFC workspace by workspace-factory)"
}

variable "dns_verification" {
  type = object({
    brevo_code             = string
    google_site            = string
    microsoft              = string
    twilio                 = string
    dmarc_cloudflare_rua   = string
    nabu_casa_remote_ui_id = string
  })
  description = "Public but domain-identifying DNS verification tokens, kept out of this public repo (set on the TFC workspace by workspace-factory)"
}
