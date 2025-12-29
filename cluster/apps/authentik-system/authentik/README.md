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

  # Policy binding to restrict access to group members only
  - model: authentik_policies.policybinding
    identifiers:
      target: !KeyOf <app>_application
      order: 0
    attrs:
      group: !KeyOf <app>_admins_group
      negate: false
      enabled: true
      timeout: 30
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

**IMPORTANT:** Update BOTH files to mount the blueprint:

1. Add to `app/kustomization.yaml` configMapGenerator files list:

```yaml
configMapGenerator:
  - name: authentik-blueprints
    files:
      - blueprints/<app>-sso.yaml # Add here
```

2. Add to `app/values.yaml` volume mount items list:

```yaml
volumes:
  - name: blueprints-custom
    configMap:
      name: authentik-blueprints
      items:
        - key: <app>-sso.yaml # Add here
          path: <app>-sso.yaml
```

Missing either step will cause the blueprint to not be discovered by Authentik.

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

### Force Blueprint Reload

To list all blueprints and their status:

```bash
kubectl exec -n authentik-system deploy/authentik-server -- ak shell -c "
from authentik.blueprints.models import BlueprintInstance
[print(f'{b.pk} - {b.name} - {b.status}') for b in BlueprintInstance.objects.all()]
"
```

To force re-apply a specific blueprint by name:

```bash
kubectl exec -n authentik-system deploy/authentik-server -- ak shell -c "
from authentik.blueprints.models import BlueprintInstance
from authentik.blueprints.v1.importer import Importer
bp = BlueprintInstance.objects.filter(name='Headlamp SSO').first()
if bp:
    importer = Importer.from_string(bp.retrieve(), bp.context)
    print(importer.apply())
else:
    print('Blueprint not found')
"
```

### OAuth Credential Rotation

Automated weekly rotation of OAuth `client_secret` via CronJob. Only the secret is rotated - `client_id` remains stable (required for integrations like kube-apiserver OIDC).

#### How It Works

1. CronJob generates new client_secret
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

Add a call to the `rotate_oauth` function (includes ExternalSecret sync):

```bash
# Rotate <App> credentials (client_secret only)
rotate_oauth "<App>" "authentik-<app>-oauth" "<APP>_OAUTH_CLIENT_SECRET" "<app>-oauth-credentials" "<app-namespace>"
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

**Headlamp Example Files:**

| Component      | Location                                                  |
| -------------- | --------------------------------------------------------- |
| Blueprint      | `app/blueprints/headlamp-sso.yaml`                        |
| OAuth Secret   | `app/authentik-headlamp-oauth.sops.yaml`                  |
| Reader RBAC    | `app/headlamp-oauth-rbac.yaml`                            |
| SecretStore    | `headlamp/app/authentik-secret-store.yaml`                |
| ExternalSecret | `headlamp/app/headlamp-oauth-external-secret.yaml`        |
| Rotation RBAC  | `headlamp/app/oauth-rotation-rbac.yaml`                   |
| User RBAC      | `headlamp/app/user-rbac.yaml`                             |

**Headlamp-specific notes:**

- Requires RS256 signing (HS256 incompatible with Headlamp)
- Uses kube-apiserver OIDC for user impersonation - see `talos/patches/control-plane/configure-api-server.yaml`
- Only `client_secret` rotates - `client_id` must be stable (referenced in kube-apiserver config)
- Requires custom email mapping for `email_verified: true` (see below)

### Adding SSO via Proxy Provider (Forward-Auth)

For applications that don't support OAuth2 natively (e.g., N8N Community Edition), use Authentik's Proxy Provider with Traefik forward-auth and standalone outposts.

#### Architecture

```text
User -> Traefik -> forwardAuth middleware -> Standalone Outpost (same namespace)
                                                  |
                                                  v (authenticated)
                   Traefik <- headers injected <- Outpost
                      |
                      v
                   Application (reads X-authentik-email header)
```

#### Step 1: Create RBAC for Outpost Deployment

Authentik needs permissions to deploy outposts to the target namespace. Create `<app>/app/authentik-outpost-rbac.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: authentik-outpost-deployer
  namespace: <app-namespace>
rules:
  - apiGroups: [""]
    resources: [secrets, services, configmaps]
    verbs: [get, create, delete, list, patch]
  - apiGroups: [apps]
    resources: [deployments]
    verbs: [get, create, delete, list, patch]
  - apiGroups: [traefik.io]
    resources: [middlewares]
    verbs: [get, create, delete, list, patch]
  - apiGroups: [monitoring.coreos.com]
    resources: [servicemonitors]
    verbs: [get, create, delete, list, patch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: authentik-outpost-deployer
  namespace: <app-namespace>
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: authentik-outpost-deployer
subjects:
  - kind: ServiceAccount
    name: authentik
    namespace: authentik-system
```

#### Step 2: Create Proxy Provider Blueprint with Standalone Outpost

Create `app/blueprints/<app>-sso.yaml`:

```yaml
# yamllint disable-file
version: 1
metadata:
  name: <App> SSO
entries:
  - id: <app>_users_group
    model: authentik_core.group
    identifiers:
      name: <App> Users
    attrs:
      name: <App> Users
  - id: <app>_provider
    model: authentik_providers_proxy.proxyprovider
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
      mode: forward_single
      external_host: https://<app>.${EXTERNAL_DOMAIN}
  - id: <app>_application
    model: authentik_core.application
    identifiers:
      slug: <app>
    attrs:
      name: <App>
      provider: !KeyOf <app>_provider
      meta_launch_url: https://<app>.${EXTERNAL_DOMAIN}

  # Policy binding to restrict access to group members only
  - model: authentik_policies.policybinding
    identifiers:
      target: !KeyOf <app>_application
      order: 0
    attrs:
      group: !KeyOf <app>_users_group
      negate: false
      enabled: true
      timeout: 30

  # Standalone outpost deployed to app namespace
  - id: <app>_outpost
    model: authentik_outposts.outpost
    identifiers:
      name: <App> Outpost
    attrs:
      type: proxy
      service_connection:
        !Find [
          authentik_outposts.kubernetesserviceconnection,
          [name, "Local Kubernetes Cluster"],
        ]
      config:
        authentik_host: https://auth.${EXTERNAL_DOMAIN}/
        kubernetes_namespace: <app-namespace>
      providers:
        - !KeyOf <app>_provider
```

**Note:** No OAuth secrets needed - proxy providers use session-based auth.

#### Step 3: Create Traefik ForwardAuth Middleware

Create middleware in `traefik/ingress/<app-namespace>/` kustomization. The base template is in `traefik/ingress/base/authentik-forward-auth.yaml`:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: authentik-forward-auth
  namespace: <app-namespace>
spec:
  forwardAuth:
    # FQDN required - Traefik resolves from its own namespace context
    # Service name format: ak-outpost-<outpost-name-slug>
    address: http://ak-outpost-<app>-outpost.<app-namespace>.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik
    trustForwardHeader: true
    authResponseHeaders:
      - X-authentik-username
      - X-authentik-groups
      - X-authentik-email
      - X-authentik-name
      - X-authentik-uid
```

**Outpost service naming:** Authentik creates services named `ak-outpost-<slug>` where slug is the lowercase, hyphenated outpost name. Example: "N8N Outpost" → `ak-outpost-n8n-outpost`.

#### Step 4: Update Application Ingress

Add outpost route and middleware to application's IngressRoute:

```yaml
spec:
  routes:
    # Authentik outpost path - required for SSO auth flow
    - kind: Rule
      match: Host(`<app>.${EXTERNAL_DOMAIN}`) && PathPrefix(`/outpost.goauthentik.io/`)
      services:
        - name: ak-outpost-<app>-outpost
          passHostHeader: true
          port: 9000
    # Main route with forward-auth
    - kind: Rule
      match: Host(`<app>.${EXTERNAL_DOMAIN}`)
      middlewares:
        - name: authentik-forward-auth
      services:
        - name: <app>
          port: 80
```

#### Step 5: Add Flux Dependency

The app's Kustomization must depend on authentik to ensure RBAC exists before outpost deployment:

```yaml
# In <app>/ks.yaml
spec:
  dependsOn:
    - name: authentik
```

#### Step 6: Configure Application

The application receives trusted headers from Authentik:

- `X-authentik-email` - User's email address
- `X-authentik-username` - Username
- `X-authentik-name` - Display name
- `X-authentik-groups` - Group memberships

Configure the application to trust and use these headers for authentication.

**N8N Example Files:**

| Component       | Location                                           |
| --------------- | -------------------------------------------------- |
| Blueprint       | `app/blueprints/n8n-sso.yaml`                      |
| Outpost RBAC    | `n8n/app/authentik-outpost-rbac.yaml`              |
| ForwardAuth     | `traefik/ingress/base/authentik-forward-auth.yaml` |
| Ingress Routes  | `traefik/ingress/n8n-system/ingress-routes.yaml`   |
| Hooks ConfigMap | `n8n/app/hooks-configmap.yaml`                     |

### Adding SSO via SAML Provider

For applications with native SAML2 support (e.g., Ceph Dashboard), use Authentik's SAML Provider.

#### SAML Architecture

```text
User -> Traefik (TLS) -> Application -> SAML redirect -> Authentik
                                      <- SAML assertion <-
```

#### Step 1: Create SAML Provider Blueprint

Create `app/blueprints/<app>-sso.yaml`:

```yaml
# yamllint disable-file
version: 1
metadata:
  name: <App> SSO
entries:
  - id: <app>_users_group
    model: authentik_core.group
    identifiers:
      name: <App> Users
    attrs:
      name: <App> Users
  - id: <app>_provider
    model: authentik_providers_saml.samlprovider
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
      acs_url: https://<app>.lan.${EXTERNAL_DOMAIN}/auth/saml2
      issuer: https://auth.${EXTERNAL_DOMAIN}
      audience: https://<app>.lan.${EXTERNAL_DOMAIN}/auth/saml2/metadata
      sp_binding: post
      signing_kp:
        !Find [
          authentik_crypto.certificatekeypair,
          [name, "authentik Self-signed Certificate"],
        ]
      sign_assertion: true
      sign_response: true
      property_mappings:
        - !Find [
            authentik_providers_saml.samlpropertymapping,
            [name, "authentik default SAML Mapping: Email"],
          ]
        - !Find [
            authentik_providers_saml.samlpropertymapping,
            [name, "authentik default SAML Mapping: Name"],
          ]
        - !Find [
            authentik_providers_saml.samlpropertymapping,
            [name, "authentik default SAML Mapping: Username"],
          ]
  - id: <app>_application
    model: authentik_core.application
    identifiers:
      slug: <app>
    attrs:
      name: <App>
      provider: !KeyOf <app>_provider
      meta_launch_url: https://<app>.lan.${EXTERNAL_DOMAIN}

  # Policy binding to restrict access to group members only
  - model: authentik_policies.policybinding
    identifiers:
      target: !KeyOf <app>_application
      order: 0
    attrs:
      group: !KeyOf <app>_users_group
      negate: false
      enabled: true
      timeout: 30
```

#### SAML Provider Key Attributes

| Attribute           | Description                                                       |
| ------------------- | ----------------------------------------------------------------- |
| `acs_url`           | Assertion Consumer Service URL (where SAML response is POSTed)    |
| `issuer`            | Authentik's entity ID (your auth domain)                          |
| `audience`          | Must match SP entity ID exactly (often the metadata URL)          |
| `sp_binding`        | `post` for HTTP-POST binding                                      |
| `signing_kp`        | Key pair for signing assertions (use self-signed cert)            |
| `property_mappings` | **Required** - Email, Name, Username mappings for SAML assertions |

#### Step 2: Configure Traefik for HTTPS Protocol Headers

When the application is behind TLS termination (Traefik terminates HTTPS), the backend sees HTTP traffic. SAML libraries (like python-saml) validate that the SAML response destination matches the request protocol.

**Add the `https-proto-header` middleware** to set `X-Forwarded-Proto: https`:

```yaml
# In traefik/ingress/<app-namespace>/kustomization.yaml
resources:
  - ../base/https-proto-header.yaml # Add this

patches:
  - target:
      kind: Middleware
      name: https-proto-header
    patch: |
      - op: replace
        path: /metadata/namespace
        value: <app-namespace>
```

```yaml
# In ingress-routes.yaml
middlewares:
  - name: https-proto-header # Add before other middlewares
  - name: lan-ip-whitelist
  - name: compress
```

**Without this middleware**, SAML login fails with:

```text
"The response was received at http://... instead of https://..."
```

#### Step 3: Configure Application SAML

Configure the application to use Authentik's SAML metadata endpoint:

```text
Metadata URL: https://auth.${EXTERNAL_DOMAIN}/application/saml/<app-slug>/metadata/
```

For applications with CLI-based SAML setup (like Ceph Dashboard), automation via sidecar is recommended. See `rook-ceph/rook-ceph-cluster/app/release.yaml` for an example using Flux postRenderers.

#### SAML vs OAuth2 vs Proxy Provider

| Aspect          | OAuth2 Provider      | Proxy Provider          | SAML Provider          |
| --------------- | -------------------- | ----------------------- | ---------------------- |
| App support     | Native OAuth2/OIDC   | Any (header-based)      | Native SAML2           |
| Secrets needed  | Yes (client creds)   | No                      | No                     |
| Outpost needed  | No                   | Yes (standalone)        | No                     |
| Ingress changes | None                 | Forward-auth middleware | X-Forwarded-Proto only |
| Common apps     | Grafana, Vaultwarden | N8N, apps without SSO   | Ceph Dashboard         |

**Ceph Dashboard Example Files:**

| Component          | Location                                        |
| ------------------ | ----------------------------------------------- |
| Blueprint          | `app/blueprints/ceph-dashboard-sso.yaml`        |
| SSO Config Sidecar | `rook-ceph/rook-ceph-cluster/app/release.yaml`  |
| HTTPS Header MW    | `traefik/ingress/base/https-proto-header.yaml`  |
| Ingress Routes     | `traefik/ingress/rook-ceph/ingress-routes.yaml` |

## Group-Based Access Control

All SSO blueprints include `authentik_policies.policybinding` to restrict application access to group members only. Without this binding, any authenticated Authentik user can access the application.

### Policy Binding Pattern

```yaml
# Policy binding to restrict access to group members only
- model: authentik_policies.policybinding
  identifiers:
    target: !KeyOf <app>_application
    order: 0
  attrs:
    group: !KeyOf <app>_users_group
    negate: false
    enabled: true
    timeout: 30
```

### Group Hierarchy

Parent/child group relationships allow role-based access with inheritance:

- Users in **child groups** automatically have access to applications bound to the **parent group**
- Use for apps with multiple roles (e.g., Grafana with Admin/Editor roles)

**Grafana Example:**

```yaml
# Parent group - all Grafana users
- id: grafana_users_group
  model: authentik_core.group
  identifiers:
    name: Grafana Users

# Child groups inherit parent access
- id: grafana_admins_group
  model: authentik_core.group
  attrs:
    parent: !KeyOf grafana_users_group

- id: grafana_editors_group
  model: authentik_core.group
  attrs:
    parent: !KeyOf grafana_users_group

# Policy binds to parent - all users in parent OR children can access
- model: authentik_policies.policybinding
  attrs:
    group: !KeyOf grafana_users_group
```

Users in `Grafana Admins` or `Grafana Editors` can access the application. Grafana then maps these groups to internal roles via the `groups` scope.

## Custom Scope Mappings

### Custom Headers for Proxy Providers

Proxy providers can inject custom HTTP headers to downstream applications using scope mappings. This is useful for:

- Shared accounts (multiple users appearing as one)
- Injecting user attributes into headers
- Custom authentication schemes

**Step 1: Create Scope Mapping**

Add to the blueprint:

```yaml
- id: <app>_custom_header_scope
  model: authentik_providers_oauth2.scopemapping
  identifiers:
    name: <App> Custom Header
  attrs:
    name: <App> Custom Header
    scope_name: ak_proxy
    description: Custom header for <app>
    expression: |
      return {
          "ak_proxy": {
              "user_attributes": {
                  "additionalHeaders": {
                      "X-Custom-Header": "static-value"
                  }
              }
          }
      }
```

For dynamic values, use Python expressions:

```python
expression: |
  return {
      "ak_proxy": {
          "user_attributes": {
              "additionalHeaders": {
                  "X-App-User": request.user.username,
                  "X-App-Email": request.user.email
              }
          }
      }
  }
```

**Step 2: Add to Provider property_mappings**

Include BOTH the default proxy scope AND custom scope:

```yaml
- id: <app>_provider
  model: authentik_providers_proxy.proxyprovider
  attrs:
    # ... other attrs ...
    property_mappings:
      # Default proxy scope - REQUIRED for proxy auth to work
      - !Find [
          authentik_providers_oauth2.scopemapping,
          [managed, "goauthentik.io/providers/proxy/scope-proxy"],
        ]
      # Custom scope mapping
      - !KeyOf <app>_custom_header_scope
```

**Important**: Omitting the default proxy scope breaks authentication. Always include both.

**Step 3: Add Header to Traefik authResponseHeaders**

Traefik only forwards headers explicitly listed in `authResponseHeaders`. Add a patch to the app's ingress kustomization:

```yaml
# In traefik/ingress/<app-namespace>/kustomization.yaml
patches:
  - target:
      kind: Middleware
      name: authentik-forward-auth
    patch: |
      # ... existing patches ...
      - op: add
        path: /spec/forwardAuth/authResponseHeaders/-
        value: X-Custom-Header
```

**Firefly III Example** (shared household finance):

Uses `X-Firefly-Household-Email` header so multiple family members share one Firefly III account:

| Component     | Location                                         |
| ------------- | ------------------------------------------------ |
| Blueprint     | `app/blueprints/firefly-iii-sso.yaml`            |
| Scope mapping | `firefly_iii_shared_email_scope`                 |
| Header        | `X-Firefly-Household-Email`                      |
| Value         | `household@firefly.local` (static)               |
| Traefik patch | `traefik/ingress/firefly-iii/kustomization.yaml` |

### email_verified Claim

**Problem**: Some OIDC consumers (notably Kubernetes API server) reject tokens with `email_verified: false`. Authentik v2025.10+ returns `email_verified: false` by default and has **no native email verification system**.

**Solution**: Create a custom scope mapping that overrides the default email mapping:

```yaml
- id: <app>_email_mapping
  model: authentik_providers_oauth2.scopemapping
  identifiers:
    name: "<App> OAuth Mapping: email verified"
  attrs:
    scope_name: email
    description: "Email claim with email_verified always true"
    expression: |
      return {
          "email": request.user.email,
          "email_verified": True,
      }
```

Then reference it in the provider's `property_mappings` using `!KeyOf` instead of the default email mapping:

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
  # Use custom email mapping instead of default
  - !KeyOf <app>_email_mapping
```

**Security note**: This is safe when:
1. Users must be in an application-specific group (via `policybinding`)
2. Authentik has no built-in email verification - the claim is purely informational
3. Environment is a trusted homelab

**Applications requiring this**: Headlamp (kube-apiserver OIDC rejects `email_verified: false`)

## Troubleshooting

1. **Blueprint shows error but no logs** - Errors stored in DB, use debug command above
2. **Database connection failures** - Check CNPG cluster health
3. **Pods CrashLoopBackOff** - Check secrets and Redis connectivity
4. **SAML schema validation error** - Check `audience` matches SP entity ID exactly, ensure `property_mappings` are included
5. **SAML HTTP vs HTTPS mismatch** - Add `https-proto-header` middleware to Traefik ingress
6. **User can access app without being in group** - Missing `policybinding` in blueprint; add policy binding to application

## References

- [authentik Documentation](https://goauthentik.io/docs/)
- [Blueprint Schema](https://raw.githubusercontent.com/goauthentik/authentik/refs/heads/main/blueprints/schema.json)
