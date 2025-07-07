#!/bin/bash
set -euo pipefail

sops --config ../secrets/.sops.yaml -e ../secrets/cloudflare-api-token.secrets.yaml > ../cluster/infrastructure/cert-manager/cloudflare-api-token.yaml

kubectl create secret generic sops-age   --namespace=flux-system   --from-file=age.agekey=../secrets/.sops.agekey