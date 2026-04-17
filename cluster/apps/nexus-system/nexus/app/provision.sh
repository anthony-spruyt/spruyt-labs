#!/bin/sh
# cluster/apps/nexus-system/nexus/app/provision.sh
#
# NOTE: Variable expansions are written as $${VAR} so Flux's envsubst leaves
# them literal (${VAR}) for the shell to expand at runtime. shellcheck sees
# the raw source and flags $${...} as PID-plus-brace — safe to ignore.
#
# shellcheck disable=SC2193
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

upsert() {
  kind="$1" name="$2" body="$3"
  code=$(curl -sS -o /dev/null -w '%{http_code}' -u "$${AUTH}" "$${API}/repositories/$${name}" || echo 000)
  if [ "$${code}" = "200" ]; then
    echo "  [$${name}] exists, updating"
    resp=$(curl -sS -w '\n%{http_code}' -X PUT -H "Content-Type: application/json" -u "$${AUTH}" -d "$${body}" "$${API}/repositories/$${kind}/$${name}")
  else
    echo "  [$${name}] creating (GET returned $${code})"
    resp=$(curl -sS -w '\n%{http_code}' -X POST -H "Content-Type: application/json" -u "$${AUTH}" -d "$${body}" "$${API}/repositories/$${kind}")
  fi
  http=$(printf '%s' "$${resp}" | tail -n1)
  bod=$(printf '%s' "$${resp}" | sed '$d')
  case "$${http}" in
  2*) : ;;
  *)
    echo "    FAILED HTTP $${http}: $${bod}"
    exit 1
    ;;
  esac
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

# docker-group with dedicated connector on 8082 (serves OCI v2 at host root)
upsert docker/group docker-group '{
  "name":"docker-group","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "group":{"memberNames":["docker-hub-proxy","ghcr-proxy","mcr-proxy","quay-proxy","k8s-registry-proxy"]},
  "docker":{"v1Enabled":false,"forceBasicAuth":false,"httpPort":8082}}'

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

# Ensure anonymous access is globally enabled
curl -sf -X PUT -H "Content-Type: application/json" -u "$${AUTH}" \
  -d '{"enabled":true,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}' \
  "$${API}/security/anonymous"

# --- envbuilder-cache push: allow admin pushes (follow-up: dedicated user) ---
# No extra privilege work needed — admin role already has full write access.

echo "Provisioning complete."
