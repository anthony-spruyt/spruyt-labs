#!/bin/bash
set -euo pipefail

template="${1:-}"
case "${template}" in
spruyt-labs | xfg | devcontainer) ;;
*)
  echo "usage: $0 <spruyt-labs|xfg|devcontainer>" >&2
  exit 1
  ;;
esac

# renovate: depName=happy datasource=npm
HAPPY_VERSION="1.2.5"

root="$(cd "$(dirname "$0")/../../.." && pwd)"
target="${root}/cluster/apps/coder-workspaces/coder-workspaces/app/coder-happy-${template}.sops.yaml"
host="$(kubectl get certificate -n happy-system -o jsonpath='{.items[0].spec.dnsNames[0]}')"
server="https://${host}"

home="$(mktemp -d)"
trap 'rm -rf "${home}"' EXIT

npm install --ignore-scripts --no-fund --no-audit --prefix "${home}/cli" "happy@${HAPPY_VERSION}" >&2

echo "Pairing ${template} against ${server}: choose the mobile app option and scan the QR code." >&2
HAPPY_SERVER_URL="${server}" HAPPY_WEBAPP_URL="${server}" HAPPY_HOME_DIR="${home}" "${home}/cli/node_modules/.bin/happy" auth login

kubectl create secret generic "coder-happy-${template}" -n coder-workspaces \
  --from-file="access.key=${home}/access.key" --dry-run=client -o yaml |
  sops -e --filename-override "${target}" --input-type yaml --output-type yaml /dev/stdin >"${home}/enc.yaml"
mv "${home}/enc.yaml" "${target}"
echo "Wrote ${target#"${root}"/}" >&2
