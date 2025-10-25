#!/usr/bin/env bash
set -euo pipefail

cd /workspaces/spruyt-labs/infra/terraform/workspace-factory
terraform init -upgrade -reconfigure
cd /workspaces/spruyt-labs/infra/terraform/workspace-factory/modules/aws-workspace
terraform init -upgrade -reconfigure
cd /workspaces/spruyt-labs/infra/terraform/workspace-factory/modules/aws-oidc-provider
terraform init -upgrade -reconfigure
cd /workspaces/spruyt-labs/infra/terraform/aws/velero-backup
terraform init -upgrade -reconfigure
cd /workspaces/spruyt-labs/infra/terraform/aws/ceph-objectstore
terraform init -upgrade -reconfigure
cd /workspaces/spruyt-labs/infra/terraform/aws/cnpg-backup
terraform init -upgrade -reconfigure
cd /workspaces/spruyt-labs/infra/terraform/aws/external-secrets-backup
terraform init -upgrade -reconfigure
