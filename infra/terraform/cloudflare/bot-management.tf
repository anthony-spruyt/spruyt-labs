# Only these are set: the API ignores some bot setting writes (add the rest once fixed), https://github.com/cloudflare/terraform-provider-cloudflare/issues/6727
resource "cloudflare_bot_management" "this" {
  zone_id               = local.zone_id
  fight_mode            = false
  is_robots_txt_managed = true
}
