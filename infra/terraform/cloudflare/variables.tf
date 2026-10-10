variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID (set on the TFC workspace by workspace-factory)"
}

variable "zone_name" {
  type        = string
  description = "Cloudflare zone (apex domain) name (set on the TFC workspace by workspace-factory)"
}

variable "home_ip" {
  type        = string
  sensitive   = true
  description = "Space-separated home public IPs or CIDRs allowed to reach Authentik admin paths (set on the TFC workspace by workspace-factory)"

  validation {
    condition     = can(regex("^[0-9A-Fa-f:./]+( [0-9A-Fa-f:./]+)*$", var.home_ip))
    error_message = "home_ip must be one or more space-separated IPv4/IPv6 addresses or CIDRs."
  }
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
