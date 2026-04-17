#!/bin/sh
# cluster/apps/nexus-system/nexus/app/provision.sh
#
# NOTE: Variable expansions are written as $${VAR} so Flux's envsubst leaves
# them literal (${VAR}) for the shell to expand at runtime. shellcheck sees
# the raw source and flags $${...} as PID-plus-brace — safe to ignore.
#
# shellcheck disable=SC2193
set -eu

if ! command -v jq >/dev/null; then
  # Image ships curl; jq fetched as static binary into writable /tmp
  # (container rootfs is read-only per KSV-0014).
  JQ_VERSION="1.7.1"
  JQ_SHA256="5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5"
  echo "Downloading jq $${JQ_VERSION}..."
  curl -fsSLo /tmp/jq \
    "https://github.com/jqlang/jq/releases/download/jq-$${JQ_VERSION}/jq-linux-amd64"
  echo "$${JQ_SHA256}  /tmp/jq" | sha256sum -c -
  chmod +x /tmp/jq
  export PATH="/tmp:$${PATH}"
fi

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

# hosted cache — NOT a member of docker-group (workspace-private).
# Gets its own connector on 8083 so envbuilder can push/pull via
# /v2/<image> directly (clients expect OCI v2 at host root, not under
# /repository/<name>/).
upsert docker/hosted envbuilder-cache '{
  "name":"envbuilder-cache","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW"},
  "docker":{"v1Enabled":false,"forceBasicAuth":false,"httpPort":8083}}'

# docker-group with dedicated connector on 8082 (serves OCI v2 at host root)
upsert docker/group docker-group '{
  "name":"docker-group","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "group":{"memberNames":["docker-hub-proxy","ghcr-proxy","mcr-proxy"]},
  "docker":{"v1Enabled":false,"forceBasicAuth":false,"httpPort":8082}}'

# --- grant privileges to anonymous role (GET-merge-PUT to preserve defaults) ---
echo "Merging privileges into anonymous role..."
existing=$(curl -sf -u "$${AUTH}" "$${API}/security/roles/anonymous")
merged=$(echo "$${existing}" | jq -c '
  .privileges |= (. + [
    "nx-repository-view-*-*-read",
    "nx-repository-view-*-*-browse",
    "nx-metrics-all",
    "nx-healthcheck-read"
  ] | unique)
')
curl -sf -X PUT -H "Content-Type: application/json" -u "$${AUTH}" \
  -d "$${merged}" "$${API}/security/roles/anonymous"

# Ensure anonymous access is globally enabled
curl -sf -X PUT -H "Content-Type: application/json" -u "$${AUTH}" \
  -d '{"enabled":true,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}' \
  "$${API}/security/anonymous"

# --- envbuilder-cache push: allow admin pushes (follow-up: dedicated user) ---
# No extra privilege work needed — admin role already has full write access.

echo "Provisioning complete."
