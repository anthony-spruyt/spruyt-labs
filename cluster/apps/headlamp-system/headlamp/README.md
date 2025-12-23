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

Headlamp uses OIDC for two purposes:

1. **UI Authentication**: Users authenticate via Authentik to access Headlamp
2. **Kubernetes API Impersonation**: The OIDC token is used to authenticate as the user against the Kubernetes API

### Kubernetes API Server OIDC

The kube-apiserver must be configured with OIDC to validate tokens from Authentik. This is set in `talos/patches/control-plane/configure-api-server.yaml`:

```yaml
oidc-issuer-url: "https://auth.${EXTERNAL_DOMAIN}/application/o/headlamp/"
oidc-client-id: "<client-id-from-authentik>"
oidc-username-claim: "email"
oidc-groups-claim: "groups"
```

**Important**: The `oidc-client-id` must match the Authentik provider's client_id and remain stable (not rotated).

### User RBAC

OIDC-authenticated users need Kubernetes RBAC permissions. The user is identified by their email (from the `oidc-username-claim`). See `app/user-rbac.yaml` for the ClusterRoleBinding.

### ExternalSecret Flow

```text
authentik-system/authentik-headlamp-oauth (SOPS: clientID, clientSecret)
    |
    v (RBAC: headlamp-oauth-reader)
headlamp-system/headlamp-oauth-credentials (ExternalSecret template)
    |
    +-- OIDC_CLIENT_ID: synced from authentik
    +-- OIDC_CLIENT_SECRET: synced from authentik
    +-- OIDC_ISSUER_URL: static in template
    +-- OIDC_SCOPES: static in template
    +-- OIDC_CALLBACK_URL: static in template
    |
    v (chart externalSecret feature)
Headlamp pods (envFrom secretRef)
```

### Required Configuration

1. **Blueprint**: `authentik-system/authentik/app/blueprints/headlamp-sso.yaml`
2. **OAuth Secret**: `authentik-system/authentik/app/authentik-headlamp-oauth.sops.yaml`
3. **Env Vars**: HEADLAMP_OIDC_* in authentik values.yaml
4. **Volume Mount**: headlamp-sso.yaml in authentik blueprints volume
5. **API Server OIDC**: `talos/patches/control-plane/configure-api-server.yaml`
6. **User RBAC**: `app/user-rbac.yaml`

## OAuth Credential Rotation

Headlamp is integrated with the Authentik OAuth rotation CronJob. Only `client_secret` rotates weekly - `client_id` remains stable (required for kube-apiserver OIDC config).

### Rotation Components

| Component       | Location                                            |
| --------------- | --------------------------------------------------- |
| Rotation Call   | `authentik/app/oauth-secret-rotation/cronjob.yaml`  |
| Secret RBAC     | `authentik/app/oauth-secret-rotation/role.yaml`     |
| ES Patch RBAC   | `headlamp/app/oauth-rotation-rbac.yaml`             |

The rotation job:

1. Generates new client_secret (client_id unchanged)
2. Updates Authentik OAuth2 provider via API
3. Patches `authentik-headlamp-oauth` secret
4. Forces ExternalSecret sync in headlamp-system

## File Reference

| Component              | Location                                           |
| ---------------------- | -------------------------------------------------- |
| HelmRelease            | `app/release.yaml`                                 |
| Helm values            | `app/values.yaml`                                  |
| SecretStore            | `app/authentik-secret-store.yaml`                  |
| ExternalSecret         | `app/headlamp-oauth-external-secret.yaml`          |
| Rotation RBAC          | `app/oauth-rotation-rbac.yaml`                     |
| User RBAC              | `app/user-rbac.yaml`                               |
| ConfigMap transformer  | `app/kustomizeconfig.yaml`                         |
| Ingress                | `traefik/traefik/ingress/headlamp-system`          |
| API Server OIDC        | `talos/patches/control-plane/configure-api-server.yaml` |

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
- [Authentik SSO Integration](../../authentik-system/authentik/README.md)
