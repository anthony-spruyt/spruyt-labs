# authentik - Identity Provider

## Overview

Open-source Identity Provider for SSO authentication across the cluster.

## Prerequisites

- CNPG operator (PostgreSQL)
- Valkey (Redis-compatible)
- cert-manager for TLS

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n authentik-system
flux get helmrelease -n flux-system authentik

# View logs
kubectl logs -n authentik-system -l app.kubernetes.io/name=authentik
```

### CNPG Database Operations

See [CNPG operator docs](../../cnpg-system/cnpg-operator/README.md#kubectl-cnpg-plugin) for `kubectl cnpg` plugin usage.

Cluster name: `authentik-cnpg-cluster`

### Adding SSO Integration (Blueprints)

#### Step 1: Create Blueprint

Create `app/blueprints/<app>-sso.yaml`:

```yaml
# yamllint disable-file
version: 1
metadata:
  name: <App> SSO
entries:
  - id: <app>_admins_group
    model: authentik_core.group
    identifiers:
      name: <App> Admins
    attrs:
      name: <App> Admins

  - id: <app>_provider
    model: authentik_providers_oauth2.oauth2provider
    identifiers:
      name: <App>
    attrs:
      authorization_flow:
        !Find [
          authentik_flows.flow,
          [slug, "default-provider-authorization-implicit-consent"],
        ]
      invalidation_flow:
        !Find [
          authentik_flows.flow,
          [slug, "default-provider-invalidation-flow"],
        ]
      client_type: confidential
      redirect_uris:
        - url: https://<app>.lan.spruyt.xyz/oauth/callback
          matching_mode: strict
      client_id: !Env <APP>_OAUTH_CLIENT_ID
      client_secret: !Env <APP>_OAUTH_CLIENT_SECRET
      property_mappings:
        - !Find [
            authentik_core.propertymapping,
            [name, "authentik default OAuth Mapping: OpenID 'openid'"],
          ]
        - !Find [
            authentik_core.propertymapping,
            [name, "authentik default OAuth Mapping: OpenID 'profile'"],
          ]
        - !Find [
            authentik_core.propertymapping,
            [name, "authentik default OAuth Mapping: OpenID 'email'"],
          ]

  - id: <app>_application
    model: authentik_core.application
    identifiers:
      slug: <app>
    attrs:
      name: <App>
      provider: !KeyOf <app>_provider
      meta_launch_url: https://<app>.lan.spruyt.xyz
```

#### Step 2: Create Dedicated OAuth Secret

Create a separate SOPS-encrypted secret for least-privilege cross-namespace access.

Generate credentials:

```bash
openssl rand -hex 32  # client_id
openssl rand -hex 32  # client_secret
```

Create `app/authentik-<app>-oauth.sops.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: authentik-<app>-oauth
  namespace: authentik-system
stringData:
  <APP>_OAUTH_CLIENT_ID: <generated>
  <APP>_OAUTH_CLIENT_SECRET: <generated>
```

Add to `app/kustomization.yaml` resources:

```yaml
- ./authentik-<app>-oauth.sops.yaml
```

#### Step 3: Mount in Authentik

Add to `app/values.yaml` under `global.env`:

```yaml
- name: <APP>_OAUTH_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: authentik-<app>-oauth
      key: <APP>_OAUTH_CLIENT_ID
- name: <APP>_OAUTH_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: authentik-<app>-oauth
      key: <APP>_OAUTH_CLIENT_SECRET
```

Add to `app/kustomization.yaml` configMapGenerator:

```yaml
- key: <app>-sso.yaml
  path: <app>-sso.yaml
```

#### Step 4: Cross-Namespace Secret Sync (if app is in different namespace)

Create in the consumer app's directory:

**ServiceAccount + SecretStore:**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: authentik-secret-reader
  namespace: <consumer-namespace>
---
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: <app>-oauth-store
  namespace: <consumer-namespace>
spec:
  provider:
    kubernetes:
      remoteNamespace: authentik-system
      server:
        url: "https://kubernetes.default.svc"
        caProvider:
          type: ConfigMap
          name: kube-root-ca.crt
          key: ca.crt
      auth:
        serviceAccount:
          name: authentik-secret-reader
```

**ExternalSecret:**

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <app>-oauth-credentials
  namespace: <consumer-namespace>
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: SecretStore
    name: <app>-oauth-store
  target:
    name: <app>-oauth-credentials
    creationPolicy: Owner
  data:
    - secretKey: <APP>_OAUTH_CLIENT_ID
      remoteRef:
        key: authentik-<app>-oauth
        property: <APP>_OAUTH_CLIENT_ID
    - secretKey: <APP>_OAUTH_CLIENT_SECRET
      remoteRef:
        key: authentik-<app>-oauth
        property: <APP>_OAUTH_CLIENT_SECRET
```

**RBAC (in authentik-system)** - create `app/<app>-oauth-rbac.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: <app>-oauth-reader
  namespace: authentik-system
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["authentik-<app>-oauth"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["authorization.k8s.io"]
    resources: ["selfsubjectrulesreviews"]
    verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: <app>-oauth-reader
  namespace: authentik-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: <app>-oauth-reader
subjects:
  - kind: ServiceAccount
    name: authentik-secret-reader
    namespace: <consumer-namespace>
```

This ensures each app can only read its own OAuth credentials.

#### Step 5: Configure Application

Use internal K8s URLs for server-to-server calls:

```yaml
auth_url: https://auth.spruyt.xyz/application/o/authorize/ # External (browser)
token_url: http://authentik-server.authentik-system/application/o/token/ # Internal
api_url: http://authentik-server.authentik-system/application/o/userinfo/ # Internal
```

Mount credentials via `envFromSecrets` or similar mechanism.

#### OAuth2Provider Required Attrs

- `authorization_flow`, `invalidation_flow` - Required flows
- `client_type: confidential` - For server-side apps
- `redirect_uris` - List with `url` and `matching_mode: strict`
- `property_mappings` - Required for userinfo to return claims:

```yaml
property_mappings:
  - !Find [
      authentik_core.propertymapping,
      [name, "authentik default OAuth Mapping: OpenID 'openid'"],
    ]
  - !Find [
      authentik_core.propertymapping,
      [name, "authentik default OAuth Mapping: OpenID 'profile'"],
    ]
  - !Find [
      authentik_core.propertymapping,
      [name, "authentik default OAuth Mapping: OpenID 'email'"],
    ]
```

**OIDC Endpoints** (no app slug in path):

- `auth_url` - External: `https://auth.example.com/application/o/authorize/`
- `token_url` - Internal: `http://authentik-server.authentik-system/application/o/token/`
- `api_url` - Internal: `http://authentik-server.authentik-system/application/o/userinfo/`

Use internal K8s service URLs for token/userinfo (server-to-server calls).

**Blueprint file format**: `# yamllint disable-file` must be on line 1.

### Debugging Blueprint Errors

```bash
kubectl exec -n authentik-system deploy/authentik-server -- ak shell -c "
from authentik.blueprints.v1.importer import Importer
from authentik.blueprints.models import BlueprintInstance
bp = BlueprintInstance.objects.filter(name='Name').first()
print(Importer.from_string(bp.retrieve(), bp.context).apply())
"
```

### OAuth Credential Rotation

Automated weekly rotation of OAuth credentials via CronJob. Credentials are updated in both Authentik (via API) and Kubernetes secrets.

#### How It Works

1. CronJob generates new client_id/client_secret
2. Updates Authentik OAuth2 provider via REST API
3. Patches the app's dedicated OAuth secret (e.g., `authentik-grafana-oauth`)
4. Forces ExternalSecret sync in consumer namespace

#### Rotation Prerequisites

- `OAUTH_ROTATION_API_TOKEN` in `authentik-secrets.sops.yaml`
- OAuth Rotation Service Account blueprint applied (creates limited-permission service account)
- ExternalSecret configured in consumer namespace (Step 4 above)

#### Service Account Blueprint

The rotation CronJob uses a dedicated service account with minimal permissions, defined in `app/blueprints/oauth-rotation-service-account.yaml`:

- **Role**: `OAuth Rotation` - permissions for `view_oauth2provider` and `change_oauth2provider` only
- **Group**: `OAuth Rotation Service Accounts`
- **User**: `oauth-rotation-service` (service account type)
- **Token**: `oauth-rotation-token` - API token set via `OAUTH_ROTATION_API_TOKEN` env var

Generate the token value and add to `authentik-secrets.sops.yaml`:

```bash
openssl rand -hex 32  # OAUTH_ROTATION_API_TOKEN
```

#### Adding a New App to Rotation

1. **Update CronJob script** (`app/oauth-secret-rotation/cronjob.yaml`):

Add a section for the new app after the existing rotation logic:

```bash
# Rotate <App> credentials
PROVIDER_NAME="<App>"
NEW_CLIENT_ID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
NEW_CLIENT_SECRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)

PROVIDER_RESPONSE=$(curl -sf \
  -H "Authorization: Bearer ${AUTHENTIK_API_TOKEN}" \
  "${AUTHENTIK_URL}/api/v3/providers/oauth2/?name=${PROVIDER_NAME}")
PROVIDER_ID=$(echo "${PROVIDER_RESPONSE}" | grep -o '"pk":[0-9]*' | head -1 | cut -d: -f2)

curl -sf -X PATCH \
  -H "Authorization: Bearer ${AUTHENTIK_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"client_id\": \"${NEW_CLIENT_ID}\", \"client_secret\": \"${NEW_CLIENT_SECRET}\"}" \
  "${AUTHENTIK_URL}/api/v3/providers/oauth2/${PROVIDER_ID}/"

kubectl patch secret authentik-<app>-oauth -n authentik-system --type='json' -p="[
  {\"op\": \"replace\", \"path\": \"/data/<APP>_OAUTH_CLIENT_ID\", \"value\": \"$(echo -n $NEW_CLIENT_ID | base64 -w0)\"},
  {\"op\": \"replace\", \"path\": \"/data/<APP>_OAUTH_CLIENT_SECRET\", \"value\": \"$(echo -n $NEW_CLIENT_SECRET | base64 -w0)\"}
]"

kubectl patch externalsecret <app>-oauth-credentials -n <consumer-namespace> \
  --type='merge' -p="{\"metadata\":{\"annotations\":{\"force-sync\":\"$(date +%s)\"}}}"
```

2. **Add RBAC for ExternalSecret patching** (in consumer app directory):

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: oauth-secret-rotation
  namespace: <consumer-namespace>
rules:
  - apiGroups: ["external-secrets.io"]
    resources: ["externalsecrets"]
    resourceNames: ["<app>-oauth-credentials"]
    verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: oauth-secret-rotation
  namespace: <consumer-namespace>
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: oauth-secret-rotation
subjects:
  - kind: ServiceAccount
    name: oauth-secret-rotation
    namespace: authentik-system
```

3. **Update CronJob Role** (`app/oauth-secret-rotation/role.yaml`):

Ensure secret keys are listed in resourceNames for patching.

#### Testing Rotation

```bash
# Trigger manual rotation
kubectl create job --from=cronjob/oauth-secret-rotation oauth-test -n authentik-system

# Watch job progress
kubectl logs -n authentik-system -l job-name=oauth-test -f

# Verify ExternalSecret synced
kubectl get externalsecret -n <consumer-namespace> <app>-oauth-credentials
```

## File Reference

| Component                | Location                                             |
| ------------------------ | ---------------------------------------------------- |
| Blueprint                | `app/blueprints/<app>-sso.yaml`                      |
| OAuth Secret             | `app/authentik-<app>-oauth.sops.yaml`                |
| Core Secrets             | `app/authentik-secrets.sops.yaml`                    |
| Helm values              | `app/values.yaml`                                    |
| OAuth Reader RBAC        | `app/<app>-oauth-rbac.yaml`                          |
| Rotation Service Account | `app/blueprints/oauth-rotation-service-account.yaml` |
| Rotation CronJob         | `app/oauth-secret-rotation/cronjob.yaml`             |
| Rotation RBAC            | `app/oauth-secret-rotation/role.yaml`                |

**Grafana Example Files:**

| Component      | Location                                                            |
| -------------- | ------------------------------------------------------------------- |
| Blueprint      | `app/blueprints/grafana-sso.yaml`                                   |
| OAuth Secret   | `app/authentik-grafana-oauth.sops.yaml`                             |
| Reader RBAC    | `app/external-secrets-rbac.yaml`                                    |
| SecretStore    | `victoria-metrics-k8s-stack/app/authentik-secret-store.yaml`        |
| ExternalSecret | `victoria-metrics-k8s-stack/app/grafana-oauth-external-secret.yaml` |
| Rotation RBAC  | `victoria-metrics-k8s-stack/app/oauth-rotation-rbac.yaml`           |

**Vaultwarden Example Files:**

| Component      | Location                                                             |
| -------------- | -------------------------------------------------------------------- |
| Blueprint      | `app/blueprints/vaultwarden-sso.yaml`                                |
| OAuth Secret   | `app/authentik-vaultwarden-oauth.sops.yaml`                          |
| Reader RBAC    | `app/external-secrets-rbac.yaml`                                     |
| SecretStore    | `vaultwarden/vaultwarden/app/authentik-secret-store.yaml`            |
| ExternalSecret | `vaultwarden/vaultwarden/app/vaultwarden-oauth-external-secret.yaml` |
| Rotation RBAC  | `vaultwarden/vaultwarden/app/oauth-rotation-rbac.yaml`               |

**Vaultwarden-specific notes:**

- Requires `testing-alpine` image tag (SSO not in stable releases yet)
- `access_token_validity: minutes=10` required (Bitwarden clients detect 5min expiry)
- `signing_key` required - must use RS256 (HS256 incompatible with Vaultwarden)
- Include `offline_access` scope for refresh tokens
- Callback URL: `https://vaultwarden.${EXTERNAL_DOMAIN}/identity/connect/oidc-signin`

## Troubleshooting

1. **Blueprint shows error but no logs** - Errors stored in DB, use debug command above
2. **Database connection failures** - Check CNPG cluster health
3. **Pods CrashLoopBackOff** - Check secrets and Redis connectivity

## References

- [authentik Documentation](https://goauthentik.io/docs/)
- [Blueprint Schema](https://raw.githubusercontent.com/goauthentik/authentik/refs/heads/main/blueprints/schema.json)
