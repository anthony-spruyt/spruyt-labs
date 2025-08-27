#!/usr/bin/env bash
set -euo pipefail

cd /workspaces/spruyt-labs/infra/terraform/aws/ceph-objectstore
terraform init -upgrade
cd /workspaces/spruyt-labs/infra/terraform/aws/account
terraform init -upgrade
cd /workspaces/spruyt-labs/infra/terraform/workspace-factory
terraform init -upgrade
