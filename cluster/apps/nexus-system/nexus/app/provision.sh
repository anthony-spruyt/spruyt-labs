#!/bin/sh
# Expansions are written $${VAR} so Flux leaves them for the shell; shellcheck flags that, hence the disables.
# shellcheck disable=SC2193,SC2195,SC2157
set -eu

echo "Waiting for Nexus writable..."
for i in $(seq 1 60); do
  status=$(curl -sf -o /dev/null -w '%{http_code}' "$${NEXUS_URL}/service/rest/v1/status/writable" || true)
  [ "$${status}" = "200" ] && {
    echo "Nexus writable"
    break
  }
  echo "  attempt $${i}: HTTP $${status}, retrying in 10s..."
  sleep 10
done
[ "$${status}" = "200" ] || {
  echo "Nexus never became writable"
  exit 1
}

AUTH="$${NEXUS_USER}:$${NEXUS_PASSWORD}"
API="$${NEXUS_URL}/service/rest/v1"
CLEANUP_POLICY="unused-90d"

check() {
  http=$(printf '%s' "$${1}" | tail -n1)
  case "$${http}" in
  2*) : ;;
  *)
    echo "    FAILED HTTP $${http}: $(printf '%s' "$${1}" | sed '$d')"
    exit 1
    ;;
  esac
}

# Public /v1/cleanup-policies is Pro-only (404 on Community); the UI's internal endpoint works.
echo "Upserting cleanup policy $${CLEANUP_POLICY}..."
POLICY_BODY='{"name":"'"$${CLEANUP_POLICY}"'","format":"*","notes":"Managed by nexus-provision-repos","criteriaLastDownloaded":90}'
POLICY_API="$${NEXUS_URL}/service/rest/internal/cleanup-policies"
code=$(curl -sS -o /dev/null -w '%{http_code}' -u "$${AUTH}" "$${POLICY_API}/$${CLEANUP_POLICY}" || echo 000)
if [ "$${code}" = "200" ]; then
  check "$(curl -sS -w '\n%{http_code}' -X PUT -H "Content-Type: application/json" -u "$${AUTH}" -d "$${POLICY_BODY}" "$${POLICY_API}/$${CLEANUP_POLICY}")"
else
  check "$(curl -sS -w '\n%{http_code}' -X POST -H "Content-Type: application/json" -u "$${AUTH}" -d "$${POLICY_BODY}" "$${POLICY_API}")"
fi

upsert() {
  kind="$1" name="$2" body="$3"
  # Group repos hold no content of their own, so they take no cleanup policy.
  case "$${kind}" in
  */group) : ;;
  *) body="{\"cleanup\":{\"policyNames\":[\"$${CLEANUP_POLICY}\"]},$${body#\{}" ;;
  esac
  code=$(curl -sS -o /dev/null -w '%{http_code}' -u "$${AUTH}" "$${API}/repositories/$${name}" || echo 000)
  if [ "$${code}" = "200" ]; then
    echo "  [$${name}] exists, updating"
    resp=$(curl -sS -w '\n%{http_code}' -X PUT -H "Content-Type: application/json" -u "$${AUTH}" -d "$${body}" "$${API}/repositories/$${kind}/$${name}")
  else
    echo "  [$${name}] creating (GET returned $${code})"
    resp=$(curl -sS -w '\n%{http_code}' -X POST -H "Content-Type: application/json" -u "$${AUTH}" -d "$${body}" "$${API}/repositories/$${kind}")
  fi
  check "$${resp}"
}

# --- apt proxies ---
upsert apt/proxy apt-ubuntu-proxy '{
  "name":"apt-ubuntu-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"http://archive.ubuntu.com/ubuntu/","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "apt":{"distribution":"jammy","flat":false}}'

upsert apt/proxy apt-cli-github '{
  "name":"apt-cli-github","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":false},
  "proxy":{"remoteUrl":"https://cli.github.com/packages/","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "apt":{"distribution":"stable","flat":true}}'

upsert apt/proxy apt-nodesource '{
  "name":"apt-nodesource","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":false},
  "proxy":{"remoteUrl":"https://deb.nodesource.com/","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "apt":{"distribution":"stable","flat":true}}'

upsert apt/proxy apt-hashicorp '{
  "name":"apt-hashicorp","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":false},
  "proxy":{"remoteUrl":"https://apt.releases.hashicorp.com/","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "apt":{"distribution":"jammy","flat":false}}'

upsert apt/proxy apt-launchpad '{
  "name":"apt-launchpad","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":false},
  "proxy":{"remoteUrl":"https://ppa.launchpadcontent.net/","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "apt":{"distribution":"stable","flat":true}}'

# --- npm / pypi proxies (pre-commit hook envs, issue #1880) ---
upsert npm/proxy npm-proxy '{
  "name":"npm-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://registry.npmjs.org","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "npm":{"removeNonCataloged":false,"removeQuarantined":false}}'

upsert pypi/proxy pypi-proxy '{
  "name":"pypi-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://pypi.org/","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true}}'

# --- docker proxies ---
upsert docker/proxy docker-hub-proxy '{
  "name":"docker-hub-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://registry-1.docker.io","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true,"authentication":{"type":"username","username":"'"$${DOCKERHUB_USER}"'","password":"'"$${DOCKERHUB_TOKEN}"'"}},
  "docker":{"v1Enabled":false,"forceBasicAuth":false},
  "dockerProxy":{"indexType":"HUB","cacheForeignLayers":false}}'

upsert docker/proxy ghcr-proxy '{
  "name":"ghcr-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://ghcr.io","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true,"authentication":{"type":"username","username":"'"$${GHCR_USER}"'","password":"'"$${GHCR_TOKEN}"'"}},
  "docker":{"v1Enabled":false,"forceBasicAuth":false},
  "dockerProxy":{"indexType":"REGISTRY","cacheForeignLayers":false}}'

upsert docker/proxy mcr-proxy '{
  "name":"mcr-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://mcr.microsoft.com","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "docker":{"v1Enabled":false,"forceBasicAuth":false},
  "dockerProxy":{"indexType":"REGISTRY","cacheForeignLayers":false}}'

upsert docker/proxy quay-proxy '{
  "name":"quay-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://quay.io","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "docker":{"v1Enabled":false,"forceBasicAuth":false},
  "dockerProxy":{"indexType":"REGISTRY","cacheForeignLayers":false}}'

upsert docker/proxy k8s-registry-proxy '{
  "name":"k8s-registry-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://registry.k8s.io","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "docker":{"v1Enabled":false,"forceBasicAuth":false},
  "dockerProxy":{"indexType":"REGISTRY","cacheForeignLayers":false}}'

# hosted cache — NOT a member of docker-group (workspace-private).
# Gets its own connector on 8083 so envbuilder can push/pull via
# /v2/<image> directly (clients expect OCI v2 at host root, not under
# /repository/<name>/).
# forceBasicAuth=true: kaniko's token-auth flow against Nexus 401-loops
# (Bearer issued but not honored on next request). Basic auth via the
# ENVBUILDER_DOCKER_CONFIG_BASE64 credentials works reliably.
upsert docker/hosted envbuilder-cache '{
  "name":"envbuilder-cache","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW"},
  "docker":{"v1Enabled":false,"forceBasicAuth":true,"httpPort":8083}}'

# docker-group with dedicated connector on 8082 (serves OCI v2 at host root).
# forceBasicAuth=true: same Nexus 3 bug as envbuilder-cache above — Bearer
# realm is advertised but anonymous bearer tokens get 401'd on the next
# request. Sonatype's documented workaround is forceBasicAuth; the Bearer
# flow on group/proxy repos has regressed repeatedly (see
# https://github.com/sonatype/nexus-public/issues/410 and
# https://github.com/sonatype/nexus-public/issues/435). Basic auth via
# the workspace-puller credentials (mounted as /etc/containers/auth.json
# in coder workspaces) works reliably. Ref #976.
upsert docker/group docker-group '{
  "name":"docker-group","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "group":{"memberNames":["docker-hub-proxy","ghcr-proxy","mcr-proxy","quay-proxy","k8s-registry-proxy"]},
  "docker":{"v1Enabled":false,"forceBasicAuth":true,"httpPort":8082}}'

# --- anonymous-extras role + assignment ---
# nx-anonymous is a built-in read-only role already granting repo view/read/
# browse. We only need to add nx-metrics-all (for VMPodScrape). Create a
# separate custom role and assign it to the anonymous user alongside
# nx-anonymous so both survive Nexus upgrades.
echo "Upserting anonymous-extras role..."
ROLE_BODY='{"id":"anonymous-extras","name":"Anonymous Extras","description":"Extra privileges for the built-in anonymous user","privileges":["nx-metrics-all","nx-healthcheck-read"],"roles":[]}'
code=$(curl -sS -o /dev/null -w '%{http_code}' -u "$${AUTH}" "$${API}/security/roles/anonymous-extras" || echo 000)
if [ "$${code}" = "200" ]; then
  curl -sfS -X PUT -H "Content-Type: application/json" -u "$${AUTH}" \
    -d "$${ROLE_BODY}" "$${API}/security/roles/anonymous-extras"
else
  curl -sfS -X POST -H "Content-Type: application/json" -u "$${AUTH}" \
    -d "$${ROLE_BODY}" "$${API}/security/roles"
fi

echo "Assigning anonymous-extras to anonymous user..."
curl -sfS -X PUT -H "Content-Type: application/json" -u "$${AUTH}" -d '{
  "userId":"anonymous","firstName":"Anonymous","lastName":"User",
  "emailAddress":"anonymous@example.org","source":"default",
  "status":"active","roles":["nx-anonymous","anonymous-extras"]
}' "$${API}/security/users/anonymous"

curl -sf -X PUT -H "Content-Type: application/json" -u "$${AUTH}" \
  -d '{"enabled":true,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}' \
  "$${API}/security/anonymous"

# --- client users: docker-group forceBasicAuth=true rejects anonymous, so docker clients need real users ---
# Passwords are ESO-generated in the nexus-clients secret (clients-eso.yaml). Ref #976, #3226, #3228.
echo "Upserting envbuilder-cache-writer role..."
ROLE_BODY='{"id":"envbuilder-cache-writer","name":"Envbuilder Cache Writer","description":"Push to envbuilder-cache only","privileges":["nx-repository-view-docker-envbuilder-cache-browse","nx-repository-view-docker-envbuilder-cache-read","nx-repository-view-docker-envbuilder-cache-add","nx-repository-view-docker-envbuilder-cache-edit"],"roles":[]}'
code=$(curl -sS -o /dev/null -w '%{http_code}' -u "$${AUTH}" "$${API}/security/roles/envbuilder-cache-writer" || echo 000)
if [ "$${code}" = "200" ]; then
  check "$(curl -sS -w '\n%{http_code}' -X PUT -H "Content-Type: application/json" -u "$${AUTH}" -d "$${ROLE_BODY}" "$${API}/security/roles/envbuilder-cache-writer")"
else
  check "$(curl -sS -w '\n%{http_code}' -X POST -H "Content-Type: application/json" -u "$${AUTH}" -d "$${ROLE_BODY}" "$${API}/security/roles")"
fi

# GET /security/users?userId= returns 200 with a list even when empty, so match on the body.
# The password is set via change-password (text/plain), so it never needs JSON escaping.
upsert_user() {
  id="$1" roles="$2" password="$3"
  body='{"userId":"'"$${id}"'","firstName":"'"$${id}"'","lastName":"Client","emailAddress":"'"$${id}"'@example.org","source":"default","status":"active","roles":'"$${roles}"'}'
  existing=$(curl -sS -u "$${AUTH}" "$${API}/security/users?userId=$${id}" || echo '[]')
  if printf '%s' "$${existing}" | grep -q '"userId"[[:space:]]*:[[:space:]]*"'"$${id}"'"'; then
    echo "  [user $${id}] exists, updating"
    check "$(curl -sS -w '\n%{http_code}' -X PUT -H "Content-Type: application/json" -u "$${AUTH}" -d "$${body}" "$${API}/security/users/$${id}")"
  else
    echo "  [user $${id}] creating"
    check "$(curl -sS -w '\n%{http_code}' -X POST -H "Content-Type: application/json" -u "$${AUTH}" -d "{\"password\":\"placeholder-will-be-rotated\",$${body#\{}" "$${API}/security/users")"
  fi
  check "$(curl -sS -w '\n%{http_code}' -X PUT -H "Content-Type: text/plain" -u "$${AUTH}" --data-binary "$${password}" "$${API}/security/users/$${id}/change-password")"
}

echo "Upserting client users..."
upsert_user workspace-puller '["nx-anonymous"]' "$${WORKSPACE_PULLER_PASSWORD}"
upsert_user envbuilder-cache '["nx-anonymous","envbuilder-cache-writer"]' "$${ENVBUILDER_CACHE_PASSWORD}"
upsert_user local-dev '["nx-anonymous"]' "$${LOCAL_DEV_PASSWORD}"

# --- scheduled tasks that turn cleanup soft-deletes into freed disk ---
# The daily 01:00 "Cleanup service" task is built in; these two are not.
# One task per type, so the first task of that type is the one we manage.
upsert_task() {
  type="$1" body="$2"
  # Check the lookup first: an empty id on a failed GET would create a duplicate task.
  resp=$(curl -sS -w '\n%{http_code}' -u "$${AUTH}" "$${API}/tasks?type=$${type}")
  check "$${resp}"
  id=$(printf '%s' "$${resp}" | sed '$d' | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' | head -n1)
  if [ -n "$${id}" ]; then
    echo "  [task $${type}] exists, updating"
    check "$(curl -sS -w '\n%{http_code}' -X PUT -H "Content-Type: application/json" -u "$${AUTH}" -d "$${body}" "$${API}/tasks/$${id}")"
  else
    echo "  [task $${type}] creating"
    check "$(curl -sS -w '\n%{http_code}' -X POST -H "Content-Type: application/json" -u "$${AUTH}" -d "{\"type\":\"$${type}\",$${body#\{}" "$${API}/tasks")"
  fi
}

echo "Upserting scheduled tasks..."
# Soft-deletes untagged layers and manifests, which includes digest-pinned proxy pulls.
# Weekly with a 30-day (720h) offset so those stay cached between re-fetches.
upsert_task repository.docker.gc '{
  "name":"docker-gc-all","enabled":true,"notificationCondition":"FAILURE",
  "frequency":{"schedule":"cron","cronExpression":"0 0 2 ? * SUN"},
  "properties":{"repositoryName":"*","deployOffset":"720"}}'
upsert_task blobstore.compact '{
  "name":"compact-default","enabled":true,"notificationCondition":"FAILURE",
  "frequency":{"schedule":"cron","cronExpression":"0 0 4 * * ?"},
  "properties":{"blobstoreName":"default","blobsOlderThan":"0"}}'

echo "Provisioning complete."
