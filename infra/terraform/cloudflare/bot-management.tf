# Only fight_mode is set: the API silently ignores some bot setting writes (remove when fixed), https://github.com/cloudflare/terraform-provider-cloudflare/issues/6727
resource "cloudflare_bot_management" "this" {
  zone_id    = local.zone_id
  fight_mode = false
}
