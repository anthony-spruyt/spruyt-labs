#!/bin/bash
set -euo pipefail

# 1) Resolve this script’s directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARDRAIL_FILE="${SCRIPT_DIR}/guardrail.yaml"

# 2) Load FLUX_TEST_PATH from config.sh
source "${SCRIPT_DIR}/config.sh"
RENDERED_FILE="${FLUX_TEST_PATH}/rendered.yaml"

if [[ ! -f "$GUARDRAIL_FILE" ]]; then
  echo "❌ guardrail definitions not found at $GUARDRAIL_FILE"
  exit 1
fi

echo "🛡️  Running guardrail checks…"

# 3) Quick exit if there's nothing to guard (no changes)
DIFF_OUT="$(kubectl diff -f "${RENDERED_FILE}" || true)"
if [[ -z "$DIFF_OUT" ]]; then
  echo "✅ No differences detected; skipping guardrail checks."
  exit 0
fi

# 4) Load critical kinds and namespaces
mapfile -t CRIT_KINDS      < <(yq e '.critical.kinds[]'      "$GUARDRAIL_FILE")
mapfile -t CRIT_NAMESPACES < <(yq e '.critical.namespaces[]' "$GUARDRAIL_FILE")

# 5) Initialize detection map
declare -A DETECTED=()

# 6) Scan only the changed docs
#    We extract Kind|Namespace from the rendered file,
#    then check if those appear in the DIFF output.
while IFS="|" read -r KIND NS; do
  # skip if this kind|ns pair did not appear in the diff text
  if ! grep -q -E "^[+-].*kind: *${KIND}" <<<"$DIFF_OUT"; then
    continue
  fi

  # mark critical kinds
  for ck in "${CRIT_KINDS[@]}"; do
    [[ "$KIND" == "$ck" ]] && DETECTED["kind::$ck"]=1
  done
  # mark critical namespaces
  for cn in "${CRIT_NAMESPACES[@]}"; do
    [[ "$NS" == "$cn" ]] && DETECTED["ns::$cn"]=1
  done
done < <(
  yq e 'select(.kind != null) | .kind + "|" + (.metadata.namespace // "")' \
    "$RENDERED_FILE"
)

# 7) Block if any critical kind or namespace was modified
if (( ${#DETECTED[@]} > 0 )); then
  echo
  echo "$(tput setaf 1)🚨 Guardrail Alert!$(tput sgr0)"
  echo "The following critical resources or namespaces were modified:"
  for key in "${!DETECTED[@]}"; do
    echo " • ${key//::/: }"
  done
  echo "Manual review required before syncing."
  exit 1
fi

echo "✅ Guardrail checks passed: no critical resources changed."