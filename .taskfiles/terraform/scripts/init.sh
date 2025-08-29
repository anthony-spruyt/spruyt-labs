#!/usr/bin/env bash
set -euo pipefail

cd /workspaces/spruyt-labs/infra/terraform/aws/ceph-objectstore
terraform init -upgrade -reconfigure
cd /workspaces/spruyt-labs/infra/terraform/workspace-factory
terraform init -upgrade -reconfigure
