# Foundry VTT

## Overview

Foundry Virtual Tabletop (Foundry VTT) is a modern, self-hosted virtual tabletop application designed for playing tabletop role-playing games over the internet. It provides dynamic lighting, token management, audio/video integration, and extensive module support.

## Prerequisites

- `foundryvtt-secrets` containing Foundry VTT license key
- Ceph RBD storage class `rbd-fast-delete` with 10Gi PVC

## Access

For external access, create ingress routes in `cluster/apps/traefik/traefik/ingress/foundryvtt/` with:

- Host: `foundryvtt.${EXTERNAL_DOMAIN}`
- TLS secret: `foundryvtt-${EXTERNAL_DOMAIN/./-}-tls`

For LAN access, use `foundryvtt.lan.${EXTERNAL_DOMAIN}`.

## Troubleshooting

1. **Foundry VTT won't start**

   - **Symptom**: Pod in CrashLoopBackoff or InitContainer failures
   - **Resolution**: Verify `foundryvtt-secrets` contains valid FOUNDRY_LICENSE_KEY; check PVC status and init container logs for permission issues

2. **High resource usage causing OOM restarts**

   - **Symptom**: Pod restarts due to OOM
   - **Resolution**: Increase memory limits in `values.yaml`; adjust UV_THREADPOOL_SIZE and NODE_OPTIONS for performance tuning based on active gaming sessions and module usage

## References

- [Foundry VTT Official Documentation](https://foundryvtt.com/article/installation/)
- [felddy/foundryvtt-docker GitHub](https://github.com/felddy/foundryvtt-docker)
- [BJW-S Labs Helm Charts](https://github.com/bjw-s-labs/helm-charts)
