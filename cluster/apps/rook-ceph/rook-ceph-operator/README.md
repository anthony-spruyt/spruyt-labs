# rook-ceph-operator - Ceph Storage Operator

## Overview

Rook Ceph Operator manages the lifecycle of Ceph storage clusters in Kubernetes, providing distributed block storage, shared filesystem storage, and object storage.

## Prerequisites

- Storage nodes must be available for Ceph cluster deployment

## Troubleshooting

1. **Helm release fails to deploy**

   - **Symptom**: HelmRelease stuck in `False` ready state
   - **Resolution**: Check rendered manifests with `flux diff hr rook-ceph-operator --namespace rook-ceph` and validate with `kubeconform -strict -summary ./cluster/apps/rook-ceph/rook-ceph-operator/app`

## References

- [Rook Ceph documentation](https://rook.io/docs/rook/latest/)
- [Rook Ceph Helm chart](https://github.com/rook/rook/tree/master/deploy/charts/rook-ceph)
