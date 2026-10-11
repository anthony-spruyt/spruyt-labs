resource "cloudflare_bot_management" "this" {
  zone_id = local.zone_id

  fight_mode            = false
  enable_js             = true
  ai_bots_protection    = "block"
  crawler_protection    = "enabled"
  is_robots_txt_managed = true
  ai_training           = "disallow"
  aisearch              = "disabled"
  ai_user               = "disabled"
}
