# Grafana SSO Integration with Authentik

## Goal

Configure Grafana to authenticate via Authentik OIDC, enabling single sign-on.

## Implementation Steps

### 1. Create OAuth2 Provider in Authentik UI

In Authentik Admin (`https://auth.spruyt.xyz/if/admin/`):

1. **Applications** → **Providers** → **Create**

   - Type: OAuth2/OpenID Provider
   - Name: `Grafana`
   - Authorization flow: `default-authorization-flow`
   - Client ID: (auto-generated, copy this)
   - Client Secret: (auto-generated, copy this)
   - Redirect URIs: `https://grafana.lan.spruyt.xyz/login/generic_oauth`
   - Signing Key: Select default

2. **Applications** → **Applications** → **Create**

   - Name: `Grafana`
   - Slug: `grafana`
   - Provider: Select the Grafana provider created above
   - Launch URL: `https://grafana.lan.spruyt.xyz`

3. **Directory** → **Groups** → Create groups for role mapping:
   - `Grafana Admins` - Admin access
   - `Grafana Editors` - Editor access
   - (Optional: assign yourself to Grafana Admins)

### 2. Create Grafana OAuth Credentials Secret

**File**: `cluster/apps/observability/victoria-metrics-k8s-stack/app/grafana-oauth-credentials.sops.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-oauth-credentials
  namespace: observability
type: Opaque
stringData:
  client-id: <CLIENT_ID_FROM_AUTHENTIK>
  client-secret: <CLIENT_SECRET_FROM_AUTHENTIK>
```

Encrypt with SOPS after adding credentials.

### 3. Update Kustomization

**File**: `cluster/apps/observability/victoria-metrics-k8s-stack/app/kustomization.yaml`

Add the new secret to resources:

```yaml
resources:
  - ./grafana-secrets.sops.yaml
  - ./grafana-oauth-credentials.sops.yaml  # ADD THIS
  - ./victoria-metrics-k8s-stack-secrets.sops.yaml
  ...
```

### 4. Update Grafana Values

**File**: `cluster/apps/observability/victoria-metrics-k8s-stack/app/values.yaml`

Add OIDC configuration to the grafana section:

```yaml
grafana:
  # ... existing config ...

  grafana.ini:
    server:
      root_url: https://grafana.lan.${EXTERNAL_DOMAIN}
    auth:
      signout_redirect_url: https://auth.${EXTERNAL_DOMAIN}/application/o/grafana/end-session/
      oauth_auto_login: false # Set true after testing works
    auth.generic_oauth:
      name: Authentik
      enabled: true
      client_id: $__file{/etc/secrets/auth_generic_oauth/client_id}
      client_secret: $__file{/etc/secrets/auth_generic_oauth/client_secret}
      scopes: openid profile email
      auth_url: https://auth.${EXTERNAL_DOMAIN}/application/o/authorize/
      token_url: https://auth.${EXTERNAL_DOMAIN}/application/o/token/
      api_url: https://auth.${EXTERNAL_DOMAIN}/application/o/userinfo/
      role_attribute_path: contains(groups, 'Grafana Admins') && 'Admin' || contains(groups, 'Grafana Editors') && 'Editor' || 'Viewer'
      allow_assign_grafana_admin: true

  extraSecretMounts:
    - name: auth-generic-oauth-secret-mount
      secretName: grafana-oauth-credentials
      defaultMode: 0440
      mountPath: /etc/secrets/auth_generic_oauth
      readOnly: true
```

### 5. Deploy and Test

1. Commit changes
2. Wait for Flux reconciliation
3. Verify Grafana pod restarts: `kubectl get pods -n observability -l app.kubernetes.io/name=grafana`
4. Access `https://grafana.lan.spruyt.xyz`
5. Click "Sign in with Authentik"
6. Authenticate via Authentik
7. Verify role mapping works (check user role in Grafana)

### 6. Enable Auto-Login (Optional)

After confirming SSO works, set `oauth_auto_login: true` to skip the Grafana login page.

## Files Modified

| File                                                                                            | Action                  |
| ----------------------------------------------------------------------------------------------- | ----------------------- |
| `cluster/apps/observability/victoria-metrics-k8s-stack/app/grafana-oauth-credentials.sops.yaml` | New - OAuth credentials |
| `cluster/apps/observability/victoria-metrics-k8s-stack/app/kustomization.yaml`                  | Add secret resource     |
| `cluster/apps/observability/victoria-metrics-k8s-stack/app/values.yaml`                         | Add OIDC config         |

## Validation

1. Grafana login page shows "Sign in with Authentik" button
2. OAuth flow redirects to Authentik
3. After auth, user lands in Grafana with correct role
4. Logout redirects to Authentik end-session

## Rollback

If issues occur:

1. Set `auth.generic_oauth.enabled: false` in values.yaml
2. Users can still log in with admin credentials from `grafana-secrets`
