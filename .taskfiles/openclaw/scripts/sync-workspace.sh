#!/usr/bin/env bash
# Copies workspace markdown files from the running OpenClaw pod back to the
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

mkdir -p "${DEST}"

# Copy each .md file from the pod workspace to the local repo
for file in $(kubectl exec -n "${NAMESPACE}" "${POD}" -c "${CONTAINER}" -- sh -c "ls ${WORKSPACE}/*.md 2>/dev/null"); do
  fname=$(basename "${file}")
  echo "Copying ${fname}..."
  kubectl cp "${NAMESPACE}/${POD}:${file}" "${DEST}/${fname}" -c "${CONTAINER}"
done

echo "Workspace files synced to ${DEST}"
echo "Review changes with: git diff ${DEST}"
