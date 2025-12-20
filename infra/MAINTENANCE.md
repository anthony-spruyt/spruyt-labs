# Infrastructure Maintenance Procedures

## Overview

This document outlines maintenance procedures for the spruyt-labs infrastructure as code (IaC) components, including Terraform workspace management, backup operations, and disaster recovery. These procedures ensure high availability and data integrity during maintenance windows for AWS resources and supporting infrastructure.

## Terraform Workspace Management

### Workspace Initialization

#### Prerequisites

- Terraform Cloud access configured
- AWS credentials available
- Repository cloned with latest changes

#### Initialization Procedure

1. **Navigate to Workspace Directory**:

   ```bash
   cd infra/terraform/aws/<workspace-name>
   ```

2. **Initialize Backend**:

   ```bash
   terraform init
   ```

3. **Verify Workspace**:

   ```bash
   terraform workspace list
   terraform workspace show
   ```

#### Workspace Initialization Validation

- Backend initialized successfully
- No errors in workspace selection
- Terraform Cloud connectivity confirmed

### Applying Changes

#### Change Application Prerequisites

- Plan reviewed and approved
- Maintenance window scheduled
- Backup of current state taken

#### Application Procedure

1. **Generate Plan**:

   ```bash
   terraform plan -out plan.tfplan
   ```

2. **Review Plan Output**:

   - Check for unexpected changes
   - Verify resource modifications

3. **Apply Changes**:

   ```bash
   terraform apply plan.tfplan
   ```

4. **Verify Application**:

   ```bash
   terraform show
   aws s3 ls s3://<bucket-name>
   ```

#### Change Application Validation

- Apply completes without errors
- AWS resources created/modified as expected
- Terraform Cloud run shows "applied" status

### Drift Detection and Remediation

#### Drift Detection

1. **Run Refresh-Only Plan**:

   ```bash
   terraform plan -refresh-only
   ```

2. **Identify Drift**:

   - Review changes from AWS state
   - Document out-of-band modifications

#### Remediation Procedure

1. **Import Drifted Resources** (if needed):

   ```bash
   terraform import <resource.address> <resource.id>
   ```

2. **Reconcile Configuration**:

   ```bash
   terraform plan
   terraform apply
   ```

#### Drift Remediation Validation

- Drift eliminated
- Configuration matches actual state
- No orphaned resources

## Backup Operations

### Velero Backups

#### Scheduled Backups

- Automatic daily backups configured via Velero
- Backup locations: AWS S3 buckets
- Retention: 30 days for daily, 365 days for weekly

#### Manual Backup

```bash
# Create backup
velero backup create <backup-name> \
  --include-namespaces <namespaces> \
  --exclude-namespaces kube-system,kube-node-lease

# Verify backup
velero backup get <backup-name>
velero backup logs <backup-name>
```

#### Velero Backup Validation

- Backup completes successfully
- Backup stored in S3
- Restore test performed quarterly

### Database Backups

#### CloudNativePG

- Automatic WAL archiving to S3
- Scheduled full backups
- Point-in-time recovery available

#### Database Manual Backup

```bash
# Create backup
kubectl -n <namespace> exec -it <cnpg-cluster>-1 -- pg_dump <database> > backup.sql

# Or use CNPG backup
kubectl -n <namespace> apply -f backup-job.yaml
```

## Disaster Recovery

### Data Recovery

#### From Velero

```bash
# Restore from backup
velero restore create <restore-name> --from-backup <backup-name>

# Verify restore
kubectl get pods -A
```

#### From Database Backups

```bash
# Restore database
kubectl -n <namespace> exec -it <cnpg-cluster>-1 -- psql < backup.sql
```

### Infrastructure Recovery

#### AWS Resource Recreation

1. **Assess Damage**:

   - Identify affected AWS resources
   - Check Terraform state integrity

2. **Rebuild Resources**:

   ```bash
   terraform plan
   terraform apply
   ```

3. **Verify Recovery**:

   - AWS resources recreated
   - Applications regain access
   - Backups remain intact

## Monitoring and Alerting

### Health Checks

- Terraform Cloud runs: Check workspace status
- AWS resources: `aws s3api get-bucket-versioning --bucket <bucket>`
- Backup status: `velero backup get`
- Database health: CNPG cluster status

### Maintenance Windows

- Schedule during low-usage periods
- Notify stakeholders in advance
- Document all changes and outcomes
- Post-maintenance validation

## References

- [Terraform CLI Documentation](https://developer.hashicorp.com/terraform/cli)
- [Terraform Cloud Workspaces](https://developer.hashicorp.com/terraform/cloud-docs/workspaces)
- [Velero Documentation](https://velero.io/docs/)
- [CloudNativePG Backup](https://cloudnative-pg.io/docs/1.28/backup)
- [AWS S3 Documentation](https://docs.aws.amazon.com/s3/)
