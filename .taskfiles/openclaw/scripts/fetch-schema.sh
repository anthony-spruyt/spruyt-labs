#!/usr/bin/env bash
# Fetches the OpenClaw config JSON Schema from the running pod via WebSocket RPC.
# The schema is written to a file inside the pod first (to avoid stdout truncation),
# then copied out via kubectl cp.
#
# Usage: bash fetch-openclaw-schema.sh [output-path]
# Default output: cluster/apps/openclaw/openclaw/app/openclaw-schema.json

set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
OUTPUT="${1:-${ROOT_DIR}/cluster/apps/openclaw/openclaw/app/openclaw-schema.json}"
NAMESPACE="openclaw"
APP_LABEL="app.kubernetes.io/name=openclaw"
CONTAINER="main"
POD_TMP="/tmp/openclaw-schema.json"

# Find the running pod
POD=$(kubectl get pods -n "${NAMESPACE}" -l "${APP_LABEL}" --no-headers -o custom-columns=":metadata.name" | head -1)
if [[ -z "${POD}" ]]; then
  echo "ERROR: No openclaw pod found in namespace ${NAMESPACE}" >&2
  exit 1
fi
echo "Using pod: ${POD}"

# Run the WebSocket RPC script inside the pod (token is already in the pod's env)
echo "Fetching config schema via gateway WebSocket..."
kubectl exec -n "${NAMESPACE}" "${POD}" -c "${CONTAINER}" -- node -e '
const WebSocket = require("ws");
const crypto = require("crypto");
const fs = require("fs");
const token = process.env.OPENCLAW_GATEWAY_TOKEN;
if (token === undefined) { console.error("No OPENCLAW_GATEWAY_TOKEN in pod env"); process.exit(1); }

const { publicKey, privateKey } = crypto.generateKeyPairSync("ed25519");
const spkiDer = publicKey.export({ type: "spki", format: "der" });
const rawPubKey = spkiDer.subarray(spkiDer.length - 32);
const pubKeyB64Url = rawPubKey.toString("base64url");
const deviceId = crypto.createHash("sha256").update(rawPubKey).digest("hex");

const clientId = "openclaw-control-ui";
const clientMode = "ui";
const role = "operator";
const scopes = ["operator.admin", "operator.config"];

const ws = new WebSocket("ws://localhost:18789", { headers: { origin: "http://localhost:18789" } });
const send = (method, params) => {
  const id = crypto.randomUUID();
  ws.send(JSON.stringify({ type: "req", id, method, params }));
};
ws.on("message", (data) => {
  const msg = JSON.parse(data.toString());
  if (msg.event === "connect.challenge") {
    const nonce = msg.payload.nonce;
    const signedAt = Date.now();
    const payload = ["v2", deviceId, clientId, clientMode, role, scopes.join(","), String(signedAt), token, nonce].join("|");
    const signature = crypto.sign(null, Buffer.from(payload, "utf8"), privateKey).toString("base64url");
    send("connect", {
      minProtocol: 3, maxProtocol: 3,
      client: { id: clientId, version: "0.0.1", platform: "web", mode: clientMode },
      role, scopes,
      auth: { token },
      device: { id: deviceId, publicKey: pubKeyB64Url, signature, signedAt, nonce }
    });
  } else if (msg.type === "res" && msg.payload && msg.payload.type === "hello-ok") {
    send("config.schema", {});
  } else if (msg.type === "res" && msg.ok && msg.payload && msg.payload.schema) {
    // Add $schema as allowed property (the upstream schema has additionalProperties: false)
    const schema = msg.payload.schema;
    if (schema.properties) {
      schema.properties["$schema"] = { type: "string" };
    }
    fs.writeFileSync("/tmp/openclaw-schema.json", JSON.stringify(schema, null, 2) + "\n");
    console.log("Schema written to pod:/tmp/openclaw-schema.json");
    process.exit(0);
  } else if (msg.type === "res" && msg.ok === false) {
    console.error("Gateway error:", JSON.stringify(msg.error));
    process.exit(1);
  }
});
ws.on("error", (err) => { console.error("WS error:", err.message); process.exit(1); });
setTimeout(() => { console.error("Timeout waiting for gateway response"); process.exit(1); }, 10000);
'

# Copy from pod to local filesystem
echo "Copying schema from pod..."
kubectl cp "${NAMESPACE}/${POD}:${POD_TMP}" "${OUTPUT}" -c "${CONTAINER}"

# Validate
if jq empty "${OUTPUT}" 2>/dev/null; then
  PROPS=$(jq '.properties | length' "${OUTPUT}")
  echo "Schema saved to ${OUTPUT} (${PROPS} top-level properties)"
else
  echo "ERROR: Output is not valid JSON" >&2
  exit 1
fi
