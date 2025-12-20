# Velero Backup System

## Summary

Velero provides comprehensive backup and disaster recovery capabilities for the spruyt-labs Kubernetes cluster. This critical component ensures data protection, cluster state preservation, and recovery capabilities for all persistent workloads.

## Preconditions

- Kubernetes cluster v1.25+ with FluxCD active
- AWS credentials configured for backup storage (S3)
- Appropriate IAM permissions for Velero service account
- Storage classes configured for volume snapshots
- Cluster-wide RBAC permissions for Velero operations

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

## References

- [Velero Official Documentation](https://velero.io/)
- [AWS Plugin Documentation](https://github.com/vmware-tanzu/velero-plugin-for-aws)
- [Disaster Recovery Guide](https://velero.io/docs/main/disaster-case/)
- [Backup Troubleshooting](https://velero.io/docs/main/troubleshooting/)
- [Helm Chart Reference](https://github.com/vmware-tanzu/helm-charts/tree/main/charts/velero)

## Change History

- **2025-12-04**: Initial documentation created during documentation maintenance workflow
