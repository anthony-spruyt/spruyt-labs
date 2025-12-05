# Velero Backup System

## Summary

Velero provides comprehensive backup and disaster recovery capabilities for the spruyt-labs Kubernetes cluster. This critical component ensures data protection, cluster state preservation, and recovery capabilities for all persistent workloads.

## Preconditions

- Kubernetes cluster v1.25+ with FluxCD active
- AWS credentials configured for backup storage (S3)
- Appropriate IAM permissions for Velero service account
- Storage classes configured for volume snapshots
- Cluster-wide RBAC permissions for Velero operations

## Directory Layout

```yaml
velero/
├── app/
│   ├── kustomization.yaml          # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values override
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Operation

### Monitoring Commands

```bash
# Check Velero deployment health
kubectl get pods -n velero --selector=app.kubernetes.io/name=velero

# Verify backup storage locations
kubectl get backupstoragelocations -n velero

# Check volume snapshot locations
kubectl get volumesnapshotlocations -n velero

# Monitor backup status
kubectl get backups -n velero --sort-by=.metadata.creationTimestamp

# Check restore operations
kubectl get restores -n velero

# Monitor resource usage
kubectl top pods -n velero
```

### Cross-Service Dependencies

```yaml
service_dependencies:
  velero:
    depends_on:
      - rook-ceph-storage
      - aws-credentials
      - cert-manager
      - cilium-networking
    depended_by:
      - disaster-recovery
      - cluster-migration
      - data-protection
    critical_path: true
    health_check_command: "kubectl get pods -n velero --selector=app.kubernetes.io/name=velero --no-headers | grep -c 'Running'"
```

## Troubleshooting

### Common Issues

#### Symptom: Backups failing to complete

**Diagnosis**:

- Check Velero logs for AWS permission errors
- Verify S3 bucket accessibility and IAM roles
- Review cluster resource inclusion/exclusion rules
- Examine volume snapshot capabilities

**Resolution**:

1. Validate AWS credentials and IAM permissions
2. Check S3 bucket policy and CORS configuration
3. Review Velero resource selection and filtering
4. Verify volume snapshot controller installation

#### Symptom: Restores not working correctly

**Diagnosis**:

- Examine restore logs for resource conflicts
- Check namespace and resource existence
- Review backup content and metadata
- Verify Velero version compatibility

**Resolution**:

1. Validate backup integrity before restore
2. Check for resource naming conflicts
3. Review restore hooks and annotations
4. Verify cluster state matches backup expectations

#### Symptom: High backup storage usage

**Diagnosis**:

- Check backup retention policies
- Review backup frequency and schedules
- Examine backup content and size
- Verify cleanup and garbage collection

**Resolution**:

1. Adjust retention periods in values.yaml
2. Optimize backup schedules and frequency
3. Implement backup size monitoring and alerts
4. Configure automatic cleanup policies

## Validation

### Expected Outcomes

1. **Deployment Success**: Velero pod shows `Running` status with no restarts
2. **Backup Functionality**: Scheduled backups complete successfully
3. **Restore Capability**: Test restores work as expected
4. **Storage Management**: Backup storage usage within defined limits
5. **Resource Efficiency**: Memory usage under 1Gi, CPU under 500m

### Validation Commands

```bash
# Verify Velero deployment status
kubectl get deployment -n velero velero -o json | jq '.status.availableReplicas'

# Check backup storage location
kubectl get backupstoragelocation -n velero default -o json | jq '.status.phase'

# Test backup creation
velero backup create test-backup --include-namespaces=default

# Verify backup status
velero backup describe test-backup

# Check restore functionality
velero restore create test-restore --from-backup test-backup

# Monitor backup schedules
kubectl get schedules -n velero
```

## Escalation

- **AWS Permission Issues**: Contact cloud infrastructure team for IAM troubleshooting
- **Storage Problems**: Engage storage team for S3 bucket configuration
- **Backup Configuration**: Consult with disaster recovery team for policy settings
- **Restore Failures**: Escalate to platform team for complex recovery scenarios

## Maintenance

### Updates

1. Review Velero release notes for breaking changes
2. Test new versions with sample backups and restores
3. Update AWS plugin versions and configurations
4. Adjust retention policies based on storage growth

### Backups

1. Velero configuration stored in Git
2. Backup metadata preserved in S3
3. Verify backup system health: `velero get backup locations`

### MCP Integration

```yaml
context7_usage:
  library_id: "velero-kubernetes-backup"
  version: "v1.12.0"
  source: "Velero official documentation"
  retrieved_at: "2025-12-04"
  used_for: "Backup system configuration and disaster recovery procedures"
```

## References

- [Velero Official Documentation](https://velero.io/)
- [AWS Plugin Documentation](https://github.com/vmware-tanzu/velero-plugin-for-aws)
- [Disaster Recovery Guide](https://velero.io/docs/main/disaster-case/)
- [Backup Troubleshooting](https://velero.io/docs/main/troubleshooting/)
- [Helm Chart Reference](https://github.com/vmware-tanzu/helm-charts/tree/main/charts/velero)

## Decision Tree for Backup Management

```yaml
start: "velero_health_check"
nodes:
  velero_health_check:
    question: "Is Velero backup system healthy?"
    command: "kubectl get pods -n velero --selector=app.kubernetes.io/name=velero --no-headers | grep -v 'Running'"
    yes: "investigate_velero"
    no: "velero_healthy"
  investigate_velero:
    action: "kubectl describe pods -n velero --selector=app.kubernetes.io/name=velero"
    log_command: "kubectl logs -n velero -l app.kubernetes.io/name=velero --tail=50"
    next: "analyze_velero_issue"
  analyze_velero_issue:
    question: "What type of Velero issue?"
    diagnostic_commands:
      - "kubectl get backupstoragelocations -n velero"
      - "velero get backup-locations"
      - "kubectl get events -n velero | grep velero"
      - "velero backup get"
    options:
      aws_permission: "AWS S3 permission problem"
      backup_failure: "Backup creation or completion issue"
      restore_problem: "Restore operation failure"
      resource_constraint: "Velero pod resource limits"
  aws_permission:
    action: "Verify AWS credentials and IAM permissions"
    commands:
      - "kubectl get secret -n velero cloud-credentials -o yaml"
      - "velero backup-location get"
    next: "apply_velero_fix"
  backup_failure:
    action: "Investigate backup creation problems"
    commands:
      - "velero backup logs <failed-backup>"
      - "kubectl get backup -n velero <failed-backup> -o yaml"
    next: "apply_velero_fix"
  restore_problem:
    action: "Troubleshoot restore operations"
    commands:
      - "velero restore logs <failed-restore>"
      - "velero restore describe <failed-restore>"
    next: "apply_velero_fix"
  resource_constraint:
    action: "Adjust Velero resource requests/limits"
    commands:
      - "kubectl top pods -n velero --selector=app.kubernetes.io/name=velero"
      - "kubectl describe nodes | grep -A 5 'Allocatable'"
    next: "apply_velero_fix"
  apply_velero_fix:
    action: "Apply appropriate Velero remediation"
    validation_commands:
      - "kubectl rollout restart deployment velero -n velero"
      - "velero install --upgrade"
    next: "verify_velero_fix"
  verify_velero_fix:
    question: "Is Velero issue resolved?"
    command: "kubectl get pods -n velero --selector=app.kubernetes.io/name=velero --no-headers | grep 'Running'"
    yes: "velero_healthy"
    no: "escalate_velero_issue"
  escalate_velero_issue:
    action: "Escalate with Velero diagnostics and AWS credentials to cloud team"
    next: "end"
  velero_healthy:
    action: "Velero backup system verified healthy"
    next: "end"
end: "end"
```

## Disaster Recovery Procedures

### Cluster Recovery Workflow

```yaml
disaster_recovery:
  steps:
    - name: "Assess damage and determine recovery scope"
      commands:
        - "velero get backups --sort-by=metadata.creationTimestamp"
        - "kubectl get nodes"
      validation: "Identify most recent viable backup"

    - name: "Prepare recovery environment"
      commands:
        - "kubectl create namespace velero --dry-run=client -o yaml | kubectl apply -f -"
        - "velero install --provider aws --plugins velero/velero-plugin-for-aws:v1.0.0 --bucket <bucket> --secret-file ./credentials-velero"
      validation: "Velero deployed and backup locations accessible"

    - name: "Execute recovery operation"
      commands:
        - "velero restore create --from-backup <backup-name>"
        - "velero restore logs <restore-name> --follow"
      validation: "Restore operation completes successfully"

    - name: "Verify recovered resources"
      commands:
        - "kubectl get all -A"
        - "kubectl get pvc -A"
        - "velero restore describe <restore-name>"
      validation: "All critical resources restored and functional"

    - name: "Post-recovery validation"
      commands:
        - "kubectl get pods -A --no-headers | grep -v 'Running'"
        - "velero get restores"
      validation: "Cluster returns to operational state"
```

## Change History

- **2025-12-04**: Initial documentation created during documentation maintenance workflow
- **Standards Compliance**: Follows spruyt-labs README template with decision trees
- **Validation**: Designed to pass `task dev-env:lint` requirements
- **Critical Component**: Essential for cluster disaster recovery capabilities
