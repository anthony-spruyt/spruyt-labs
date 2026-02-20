#!/usr/bin/env bash
# Copies the entire workspace folder from the running OpenClaw pod back to the
# local repo so runtime changes (e.g. agent edits) can be committed.
#
# Usage: bash sync-workspace.sh

set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
DEST="${ROOT_DIR}/cluster/apps/openclaw/openclaw/app/workspace"
NAMESPACE="openclaw"
APP_LABEL="app.kubernetes.io/name=openclaw"
CONTAINER="main"
WORKSPACE="/home/node/.openclaw/workspace"

# Find the running pod
POD=$(kubectl get pods -n "${NAMESPACE}" -l "${APP_LABEL}" --no-headers -o custom-columns=":metadata.name" | head -1)
if [[ -z "${POD}" ]]; then
  echo "ERROR: No openclaw pod found in namespace ${NAMESPACE}" >&2
  exit 1
fi
echo "Using pod: ${POD}"

# Remove existing destination so deleted files on the pod are reflected locally
rm -rf "${DEST}"
mkdir -p "${DEST}"

# Copy the entire workspace folder from the pod to the local repo
echo "Syncing workspace folder..."
kubectl cp "${NAMESPACE}/${POD}:${WORKSPACE}" "${DEST}" -c "${CONTAINER}"

echo "Workspace synced to ${DEST}"
echo "Review changes with: git diff ${DEST}"
