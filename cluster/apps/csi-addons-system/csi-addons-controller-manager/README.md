# CSI Addons Controller Manager - Storage Addons Management

## Overview

CSI Addons Controller Manager extends CSI drivers with additional capabilities not covered by the core CSI specification. It provides APIs and controllers for operations like reclaiming unused space on storage volumes, managing network fences for storage isolation, and handling encryption key lifecycle management.

The controller manager runs as a deployment in the csi-addons-system namespace and manages custom resources for these extended operations.

## References

- [CSI Addons Documentation](https://github.com/csi-addons/kubernetes-csi-addons)
- [Reclaimspace Documentation](https://github.com/csi-addons/kubernetes-csi-addons/blob/v0.13.0/docs/reclaimspace.md)
