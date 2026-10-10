resource "cloudflare_zero_trust_access_service_token" "litellm_ci" {
  account_id = var.cloudflare_account_id
  name       = "litellm-ci"
  duration   = "forever"
}

resource "cloudflare_zero_trust_access_policy" "litellm_ci" {
  account_id = var.cloudflare_account_id
  name       = "litellm-ci-service-token"
  decision   = "non_identity"

  include = [
    {
      service_token = { token_id = cloudflare_zero_trust_access_service_token.litellm_ci.id }
    },
  ]
}

resource "cloudflare_zero_trust_access_application" "litellm" {
  account_id           = var.cloudflare_account_id
  name                 = "litellm-ci"
  type                 = "self_hosted"
  domain               = local.litellm_host
  app_launcher_visible = false

  policies = [
    {
      id         = cloudflare_zero_trust_access_policy.litellm_ci.id
      precedence = 1
    },
  ]
}
