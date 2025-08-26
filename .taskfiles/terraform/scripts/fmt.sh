#!/usr/bin/env bash
set -euo pipefail

cd /workspaces/spruyt-labs/infra/terraform
terraform fmt -recursive
