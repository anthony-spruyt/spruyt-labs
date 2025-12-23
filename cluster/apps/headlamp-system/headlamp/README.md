# Headlamp - Kubernetes Dashboard

## Overview

CNCF/kubernetes-sigs Kubernetes dashboard with Flux plugin for GitOps visualization. Provides in-cluster UI for viewing Flux Kustomizations, HelmReleases, and Sources.

## Prerequisites

- Authentik (OIDC SSO)
- External Secrets operator
- cert-manager for TLS
- Traefik ingress

## Access

- **URL**: `https://headlamp.lan.${EXTERNAL_DOMAIN}`
- **Auth**: Authentik OIDC (Headlamp Users group)

## Operation

### Key Commands

```bash
# Check status
kubectl get hr -n headlamp-system headlamp
kubectl get pod -n headlamp-system

# View logs
kubectl logs -n headlamp-system -l app.kubernetes.io/name=headlamp -c headlamp
kubectl logs -n headlamp-system -l app.kubernetes.io/name=headlamp -c headlamp-plugin

# Check ExternalSecret sync
kubectl get externalsecret -n headlamp-system

# Verify certificate
kubectl get certificate -n headlamp-system
```

## Plugins

Headlamp supports plugins from ArtifactHub. Plugin installation is managed via the `pluginsManager` sidecar.

### Plugin Configuration Format

Plugins must be configured with:

- **name**: Must match pattern `^[a-z0-9][a-z0-9-_]*[a-z0-9-]$` (no `@` scopes)
- **source**: Must be ArtifactHub URL format `https://artifacthub.io/packages/headlamp/<repo>/<plugin>`
- **version**: Plugin version

```yaml
pluginsManager:
  enabled: true
  configContent: |
    plugins:
      - name: headlamp_flux
        source: https://artifacthub.io/packages/headlamp/headlamp-plugins/headlamp_flux
        version: 0.5.0
    installOptions:
      parallel: true
      maxConcurrent: 2
```

### Available Plugins

| Plugin                | ArtifactHub URL                                                             | Description             |
| --------------------- | --------------------------------------------------------------------------- | ----------------------- |
| Flux                  | `https://artifacthub.io/packages/headlamp/headlamp-plugins/headlamp_flux`   | GitOps visualization    |
| cert-manager (future) | `https://artifacthub.io/packages/headlamp/headlamp-plugins/<plugin-name>`   | Certificate management  |
| Prometheus (future)   | `https://artifacthub.io/packages/headlamp/headlamp-plugins/<plugin-name>`   | Metrics visualization   |

### Plugin Installation Troubleshooting

Plugin installation logs are in the `headlamp-plugin` container:

```bash
kubectl logs -n headlamp-system -l app.kubernetes.io/name=headlamp -c headlamp-plugin
```

Common errors:

| Error                                    | Cause                             | Fix                                  |
| ---------------------------------------- | --------------------------------- | ------------------------------------ |
| `name must match pattern`                | Used `@org/plugin` npm format     | Use `plugin_name` ArtifactHub format |
| `source must match pattern`              | Used npmjs.com URL                | Use `artifacthub.io/packages/...`    |
| `Installation failed`                    | Network/version issue             | Check version exists on ArtifactHub  |

## OIDC Configuration

Uses Authentik blueprint for SSO. The chart's native `externalSecret` feature syncs credentials from `authentik-system` namespace.

### ExternalSecret Flow

```text
authentik-system/authentik-headlamp-oauth (SOPS secret)
    |
    v (RBAC: headlamp-oauth-reader)
headlamp-system/headlamp-oauth-credentials (synced secret)
    |
    v (chart externalSecret feature)
Headlamp pods (OIDC env vars)
```

### Required Authentik Configuration

1. **Blueprint**: `authentik-system/authentik/app/blueprints/headlamp-sso.yaml`
2. **OAuth Secret**: `authentik-system/authentik/app/authentik-headlamp-oauth.sops.yaml`
3. **Env Vars**: HEADLAMP_OIDC_* in authentik values.yaml
4. **Volume Mount**: headlamp-sso.yaml in authentik blueprints volume

## OAuth Credential Rotation

Headlamp is integrated with the Authentik OAuth rotation CronJob. Credentials rotate weekly.

### Rotation Components

| Component       | Location                                            |
| --------------- | --------------------------------------------------- |
| Rotation Call   | `authentik/app/oauth-secret-rotation/cronjob.yaml`  |
| Secret RBAC     | `authentik/app/oauth-secret-rotation/role.yaml`     |
| ES Patch RBAC   | `headlamp/app/oauth-rotation-rbac.yaml`             |

The rotation job:

1. Generates new client_id/client_secret
2. Updates Authentik OAuth2 provider via API
3. Patches `authentik-headlamp-oauth` secret
4. Forces ExternalSecret sync in headlamp-system

## File Reference

| Component              | Location                                  |
| ---------------------- | ----------------------------------------- |
| HelmRelease            | `app/release.yaml`                        |
| Helm values            | `app/values.yaml`                         |
| SecretStore            | `app/authentik-secret-store.yaml`         |
| ExternalSecret         | `app/headlamp-oauth-external-secret.yaml` |
| Rotation RBAC          | `app/oauth-rotation-rbac.yaml`            |
| ConfigMap transformer  | `app/kustomizeconfig.yaml`                |
| Ingress                | `traefik/traefik/ingress/headlamp-system` |

## Troubleshooting

### Common Issues

1. **Plugin install fails**

   Check plugin container logs. Plugin name must be lowercase alphanumeric (no `@` org prefix), source must be ArtifactHub URL.

2. **OIDC login fails**

   - Verify ExternalSecret is synced: `kubectl get es -n headlamp-system`
   - Check Authentik blueprint applied: look for "Headlamp SSO" in Authentik admin
   - Verify certificate is ready: `kubectl get cert -n headlamp-system`

3. **Kubeconfig errors in logs**

   Normal - Headlamp attempts to load kubeconfig files that don't exist in-cluster. Uses serviceaccount token instead.

## References

- [Headlamp Documentation](https://headlamp.dev/docs/latest/)
- [Helm Chart](https://github.com/kubernetes-sigs/headlamp/tree/main/charts/headlamp)
- [Default Values](https://github.com/kubernetes-sigs/headlamp/blob/main/charts/headlamp/values.yaml)
- [Flux Plugin](https://artifacthub.io/packages/headlamp/headlamp-plugins/headlamp_flux)
- [Authentik SSO Integration](../authentik-system/authentik/README.md)
