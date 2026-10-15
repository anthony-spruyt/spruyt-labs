# One-shot adoption of the existing zone redirect entrypoint. Delete this file after the first apply.

data "cloudflare_rulesets" "import" {
  zone_id = local.zone_id
}

locals {
  import_ruleset_ids = {
    for r in data.cloudflare_rulesets.import.rulesets : r.phase => r.id if r.kind == "zone"
  }
}

import {
  to = cloudflare_ruleset.redirect
  id = "zones/${local.zone_id}/${local.import_ruleset_ids["http_request_dynamic_redirect"]}"
}
