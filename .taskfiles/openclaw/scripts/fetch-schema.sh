#!/usr/bin/env bash
# Fetches the OpenClaw config JSON Schema by spinning up a local container,
# starting the gateway in token auth mode, and using `openclaw gateway call`
# to retrieve the schema — no cluster auth complications.
#
# Usage: bash fetch-schema.sh [output-path]
# Default output: cluster/apps/openclaw/openclaw/app/openclaw-schema.json

set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
OUTPUT="${1:-${ROOT_DIR}/cluster/apps/openclaw/openclaw/app/openclaw-schema.json}"
CONTAINER_NAME="openclaw-schema-fetch"
TOKEN="openclaw-schema-fetch-token"
IMAGE="ghcr.io/openclaw/openclaw"

# Determine the image tag from the HelmRelease values.yaml (tag: &tag "x.y.z" pattern)
CHART_VERSION=$(grep -E 'tag: &tag ' \
  "${ROOT_DIR}/cluster/apps/openclaw/openclaw/app/values.yaml" \
  | grep -oP '"\K[^"]+' | head -1)
if [[ -n "${CHART_VERSION}" ]]; then
  IMAGE="${IMAGE}:${CHART_VERSION}"
fi
echo "Using image: ${IMAGE}"

# Clean up any leftover container
docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

# Start the gateway in token auth mode (loopback bind by default)
echo "Starting local openclaw gateway..."
docker run -d --name "${CONTAINER_NAME}" \
  -e OPENCLAW_GATEWAY_TOKEN="${TOKEN}" \
  "${IMAGE}" \
  node openclaw.mjs gateway --allow-unconfigured --auth token

# Wait for gateway to be ready
echo "Waiting for gateway to start..."
for i in $(seq 1 15); do
  if docker exec "${CONTAINER_NAME}" \
    node openclaw.mjs gateway call health --token "${TOKEN}" --json >/dev/null 2>&1; then
    echo "Gateway ready."
    break
  fi
  if [[ "${i}" -eq 15 ]]; then
    echo "ERROR: Gateway did not start in time" >&2
    docker logs "${CONTAINER_NAME}" >&2
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    exit 1
  fi
  sleep 1
done

# Fetch the schema via gateway call
echo "Fetching config schema..."
RAW=$(docker exec "${CONTAINER_NAME}" \
  node openclaw.mjs gateway call config.schema --json --token "${TOKEN}" 2>&1)

# Clean up container
docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

# Extract the schema and add $schema as allowed property
echo "${RAW}" | jq '.schema | .properties["$schema"] = {"type": "string"}' > "${OUTPUT}"

# Validate
if jq empty "${OUTPUT}" 2>/dev/null; then
  PROPS=$(jq '.properties | length' "${OUTPUT}")
  echo "Schema saved to ${OUTPUT} (${PROPS} top-level properties)"
else
  echo "ERROR: Output is not valid JSON" >&2
  exit 1
fi
