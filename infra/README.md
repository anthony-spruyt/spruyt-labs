# Infrastructure Terraform Runbook

## Purpose and Scope

This document governs the Terraform-backed infrastructure that supports the
spruyt-labs Talos cluster. It explains how directories under
[`infra/`](infra) are organized, prescribes operator workflows for planning
and applying changes, captures validation expectations, and enumerates
troubleshooting paths for Terraform Cloud backed deployments.

## Prerequisites

- Operate from the repository devcontainer or install Terraform CLI v1.6+, the
  AWS CLI, `tflint`, and `task`.
- Hold Terraform Cloud organization access for the workspaces listed below.
- Retain AWS credentials (role assumption permissions or workload identity
  configuration) aligned with
  [`terraform/workspace-factory/`](terraform/workspace-factory).
- Ensure network reachability to Terraform Cloud and the target AWS regions.

## Directory Layout

- [`terraform/aws/`](terraform/aws) — Environment-specific Terraform
  Cloud workspaces, each with an isolated backend, `.terraform.lock.hcl`, and
  workspace level variables.
- [`terraform/aws/ceph-objectstore/`](terraform/aws/ceph-objectstore) —
  Provisions S3 object storage and IAM integration consumed by
  [`cluster/apps/rook-ceph/`](cluster/apps/rook-ceph).
- [`terraform/aws/cnpg-backup/`](terraform/aws/cnpg-backup) —
  Manages CloudNativePG backup storage. Additional usage notes live in
  [`terraform/aws/cnpg-backup/README.md`](terraform/aws/cnpg-backup/README.md).
- [`terraform/aws/external-secrets/`](terraform/aws/external-secrets) —
  Supplies External Secrets Operator dependencies such as S3 secret backends and
  IAM roles.
- [`terraform/aws/velero-backup/`](terraform/aws/velero-backup) —
  Defines Velero backup buckets and IAM users. Extra guidance is captured in
  [`terraform/aws/velero-backup/README.md`](terraform/aws/velero-backup/README.md).
- [`terraform/workspace-factory/`](terraform/workspace-factory) —
  Bootstraps Terraform Cloud workspaces and AWS workload identity roles. Reusable
  modules live under
  [`terraform/workspace-factory/modules/`](terraform/workspace-factory/modules).
- [`terraform/workspace-factory/variables.auto.tfvars`](terraform/workspace-factory/variables.auto.tfvars)
  — Shared configuration for workspace bootstrap runs. Sensitive values belong
  in Terraform Cloud variable sets, not version control.

Remote state for every workspace is stored in Terraform Cloud. Avoid local state
files and rely on Terraform Cloud runs or authenticated CLI operations.

## Operational Runbook

### Summary

Operate and maintain Terraform Cloud backed infrastructure for spruyt-labs,
covering preparation, plan and apply lifecycles, drift detection, bootstrap
tasks, and remediation when runs fail.

### Preconditions

- Confirm Terraform Cloud workspace access for the expected names:
  `ceph-objectstore`, `cnpg-backup`, `external-secrets`, `velero-backup`, and
  `workspace-factory`.
- Verify AWS credentials through `aws sts get-caller-identity` before applying.
- Ensure pending infrastructure changes are committed or staged for review.
- Complete baseline linting (`task terraform:fmt`, `task terraform:validate`,
  `tflint`) and repository level preflight checks as described in
  [`README.md`](README.md).

### Procedure

#### Phase 1 – Environment Preparation

1. Authenticate with Terraform Cloud if needed.

   ```bash
   terraform login
   ```

2. Navigate to the target workspace directory and initialize the backend.

   ```bash
   cd infra/terraform/aws/velero-backup
   terraform init
   ```

   To initialize all workspaces at once, run:

   ```bash
   task terraform:init
   ```

3. Export or assume AWS credentials that align with the target environment.

   ```bash
   export AWS_PROFILE=spruyt-labs
   aws sts get-caller-identity
   ```

4. Confirm the linked Terraform Cloud workspace.

   ```bash
   terraform workspace list
   terraform workspace show
   ```

#### Phase 2 – Plan and Review

1. Format and validate configuration.

   ```bash
   task terraform:fmt
   task terraform:validate
   tflint
   ```

2. Generate a plan locally.

   ```bash
   terraform plan -out plan.tfplan
   ```

   Use `-var-file` flags to test non-default inputs when necessary.

3. For Terraform Cloud speculative runs, push the branch or trigger a run
   through the Terraform Cloud UI, capturing the run URL in pull request notes.

#### Phase 3 – Apply and Monitor

1. Apply the reviewed plan.

   ```bash
   terraform apply plan.tfplan
   ```

   From Terraform Cloud, use the "Confirm & Apply" action after reviewer
   approval.

2. Observe apply output. Validate AWS resource creation where appropriate.

   ```bash
   aws s3 ls s3://<bucket-name>
   ```

3. Update Kubernetes manifests or secrets that rely on changed outputs, such as
   object storage credentials referenced by Flux managed workloads.

#### Phase 4 – Drift Detection and State Maintenance

1. Schedule regular drift checks.

   ```bash
   terraform plan -refresh-only
   ```

2. Inspect state contents when unexpected resources appear.

   ```bash
   terraform state list
   terraform state show <resource>
   ```

3. Clear stale locks only after verifying no active runs remain.

   ```bash
   terraform force-unlock <LOCK_ID>
   ```

#### Phase 5 – Bootstrap and One-off Operations

1. Provision new Terraform Cloud workspaces via the workspace factory.

   ```bash
   cd infra/terraform/workspace-factory
   terraform init
   terraform plan -out plan.tfplan
   terraform apply plan.tfplan
   ```

2. Confirm generated workspaces inherit the correct VCS settings and variable
   sets before enabling automated runs.

3. Document any temporary bootstrap scripts in this README and retire them once
   they are automated.

#### Phase 6 – Rollback and Remediation

1. When an apply fails, review Terraform Cloud logs and target the failing
   resource.

   ```bash
   terraform apply -target=<module.resource>
   ```

2. Revert undesired changes by rolling back the Git commit and applying the
   rollback plan.

   ```bash
   terraform plan -out rollback.tfplan
   terraform apply rollback.tfplan
   ```

3. For destructive misconfigurations, re-import affected resources and re-run
   the apply after fixing configuration drift.

   ```bash
   terraform import <module.resource> <identifier>
   ```

### Validation

- Confirm Terraform Cloud runs end in `applied` status with no pending actions.
- Validate AWS resources, such as bucket versioning and encryption flags, through
  the AWS CLI or console.
- Ensure downstream Kubernetes components reconcile cleanly by checking Flux and
  secret updates.
- Capture output values in pull request notes and update dependent manifests as
  required.

### Troubleshooting Reference

See the dedicated [Troubleshooting](#troubleshooting) section for common
remediation commands covering authentication, drift, and failed applies.

### Escalation

- Record Terraform Cloud run URLs, error logs, and relevant AWS CloudTrail
  events.
- Engage the platform automation owner if remediation exceeds 60 minutes or
  requires IAM policy changes.
- Coordinate with Talos or Flux maintainers (refer to
  [`cluster/flux/README.md`](../cluster/flux/README.md)) when infrastructure
  adjustments impact cluster reconciliation.

## Validation and Testing

- `task terraform:fmt` — formats all workspaces under
  [`infra/terraform/`](terraform).
- `task terraform:validate` — executes aggregate validation scripts across
  modules and workspaces.
- `tflint` — enforces Terraform style and policy rules locally before raising
  pull requests.
- `terraform validate` — confirms syntactic correctness within the active
  workspace.
- GitHub Actions super-linter (`.github/workflows/lint.yaml`) runs
  `terraform fmt`, `terraform validate`, and `tflint` on pull requests.
- Manual post-apply checks:
  - `aws s3api get-bucket-versioning --bucket <bucket>` to confirm versioning.
  - `aws iam get-user --user-name <user>` to verify IAM configuration.
  - `kubectl -n <namespace> get secret <name> -o yaml` to validate Flux managed
    secrets.

## Troubleshooting

### Remote State Lock Contention

- Identify the lock owner in Terraform Cloud run history.
- Clear stale locks only after confirming no teammates are mid-apply.

  ```bash
  terraform force-unlock <LOCK_ID>
  ```

### Authentication Failures

- Re-authenticate to Terraform Cloud and refresh AWS credentials.

  ```bash
  terraform login
  aws sts get-caller-identity
  ```

- Verify Terraform Cloud variable sets contain required tokens and update them if
  values rotated.

### Unexpected Drift

- Surface out-of-band changes with a refresh only plan.

  ```bash
  terraform plan -refresh-only
  ```

- Import missing resources before reconciling configuration.

  ```bash
  terraform import <module.resource> <identifier>
  ```

### Failed Applies or Partial Applies

- Inspect run logs and AWS CloudTrail events to isolate the failing resource.
- Retry idempotent resources with targeted applies.

  ```bash
  terraform apply -target=<module.resource>
  ```

- Remove orphaned assets manually (for example, S3 buckets blocking deletion)
  before re-running the apply.

## References and Cross-links

<!-- markdownlint-disable MD013 -->

- Runbook standards overview:
  [`README.md#runbook-standards`](../README.md#runbook-standards)
- Flux GitOps operations:
  [`cluster/flux/README.md`](../cluster/flux/README.md)
- Talos platform guidance:
  [`talos/README.md`](../talos/README.md)
- Terraform CLI reference:
  <https://developer.hashicorp.com/terraform/cli>
- Terraform Cloud workspace management:
  <https://developer.hashicorp.com/terraform/cloud-docs/workspaces>
- TFLint rules and policies:
  <https://github.com/terraform-linters/tflint>

<!-- markdownlint-enable MD013 -->

## Change Log

- TBD — record future README updates in `yyyy-mm-dd · summary · PR/commit`
  format.
