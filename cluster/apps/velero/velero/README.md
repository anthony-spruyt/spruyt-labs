# Velero - Backup and Disaster Recovery

## Overview

Velero provides comprehensive backup and disaster recovery capabilities for the cluster. Ensures data protection, cluster state preservation, and recovery capabilities for all persistent workloads.

## Prerequisites

- AWS credentials configured for backup storage (S3)
- IAM permissions for Velero service account

## Troubleshooting

1. **Backups failing to complete**

   - **Symptom**: Backup status shows `PartiallyFailed` or `Failed`
   - **Resolution**: Check Velero logs for AWS permission errors. Verify S3 bucket accessibility and IAM roles. Review resource inclusion/exclusion rules.

2. **Restores not working correctly**

   - **Symptom**: Restore completes but resources missing or conflicting
   - **Resolution**: Validate backup integrity before restore. Check for resource naming conflicts. Review restore hooks and annotations.

## References

- [Velero Official Documentation](https://velero.io/)
- [AWS Plugin Documentation](https://github.com/vmware-tanzu/velero-plugin-for-aws)
- [Disaster Recovery Guide](https://velero.io/docs/main/disaster-case/)
- [Backup Troubleshooting](https://velero.io/docs/main/troubleshooting/)
