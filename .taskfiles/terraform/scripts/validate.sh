#!/usr/bin/env bash
set -euo pipefail

cd /workspaces/spruyt-labs/infra/terraform/workspace-factory
terraform validate
cd /workspaces/spruyt-labs/infra/terraform/workspace-factory/modules/aws-workspace
terraform validate
cd /workspaces/spruyt-labs/infra/terraform/workspace-factory/modules/aws-oidc-provider
terraform validate
cd /workspaces/spruyt-labs/infra/terraform/aws/velero-backup
terraform validate
cd /workspaces/spruyt-labs/infra/terraform/aws/ceph-objectstore
terraform validate
