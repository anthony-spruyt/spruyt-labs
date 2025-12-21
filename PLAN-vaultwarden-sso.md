# Plan: Add Vaultwarden SSO + Update Documentation

## References

- **Vaultwarden SSO Wiki**: <https://github.com/dani-garcia/vaultwarden/wiki/Enabling-SSO-support-using-OpenId-Connect>
- **Context7 Vaultwarden Docs**: `/dani-garcia/vaultwarden`

## Overview

Add SSO to Vaultwarden using Authentik, following the Grafana SSO pattern. Update documentation afterward based on learnings from onboarding the 2nd workload. Also update CLAUDE.md to reinforce Context7 usage.

## Phase 1: Test Testing Image Tag (Safety Check)

**Goal**: Verify Vaultwarden works with `:testing` tag before adding SSO

### File to Modify

`cluster/apps/vaultwarden/vaultwarden/app/values.yaml`

- Change: `tag: 1.34.3-alpine` → `tag: testing-alpine`

**Note**: No versioned testing tags exist - only `testing`, `testing-alpine`, `testing-debian`

### Validation

- Push, wait for Flux reconcile
- Verify Vaultwarden UI loads and existing data accessible
- If broken: revert immediately

---

## Phase 2: Add Vaultwarden SSO

### 2.1 Create Authentik Blueprint

**File**: `cluster/apps/authentik-system/authentik/app/blueprints/vaultwarden-sso.yaml`

Content based on grafana-sso.yaml:

- Groups: `Vaultwarden Users` (no admin/editor distinction - VW uses master password)
- OAuth2Provider: `Vaultwarden`
  - redirect_uri: `https://vaultwarden.${EXTERNAL_DOMAIN}/identity/connect/oidc-signin`
  - client_id/secret from env vars
  - **CRITICAL**: Set `access_token_validity: minutes=10` (must be >5 min, Bitwarden detects 5min expiry)
  - Include `offline_access` scope
  - Signing algorithm: RS256 (HS256 incompatible)
- Application: slug `vaultwarden`

### 2.2 Create OAuth Secret (SOPS)

**File**: `cluster/apps/authentik-system/authentik/app/authentik-vaultwarden-oauth.sops.yaml`

Keys:

- `VAULTWARDEN_OAUTH_CLIENT_ID` (generate with `openssl rand -hex 32`)
- `VAULTWARDEN_OAUTH_CLIENT_SECRET` (generate with `openssl rand -hex 64`)

Add annotation: `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` (for future rotation)

### 2.3 Update Authentik Config

**File**: `cluster/apps/authentik-system/authentik/app/kustomization.yaml`

- Add `authentik-vaultwarden-oauth.sops.yaml` to resources
- Add blueprint to configMapGenerator files

**File**: `cluster/apps/authentik-system/authentik/app/values.yaml`

- Add env vars: `VAULTWARDEN_OAUTH_CLIENT_ID`, `VAULTWARDEN_OAUTH_CLIENT_SECRET`

### 2.4 Add Cross-Namespace Secret Access (Vaultwarden side)

**File**: `cluster/apps/vaultwarden/vaultwarden/app/authentik-secret-store.yaml` (CREATE)

Create:

- ServiceAccount: `authentik-secret-reader` in vaultwarden namespace
- SecretStore: `vaultwarden-oauth-store` pointing to authentik-system

### 2.5 Add ExternalSecret

**File**: `cluster/apps/vaultwarden/vaultwarden/app/vaultwarden-oauth-external-secret.yaml` (CREATE)

ExternalSecret mapping from `authentik-vaultwarden-oauth` in authentik-system:

- `SSO_CLIENT_ID` ← `VAULTWARDEN_OAUTH_CLIENT_ID`
- `SSO_CLIENT_SECRET` ← `VAULTWARDEN_OAUTH_CLIENT_SECRET`

### 2.6 Add RBAC in authentik-system

**File**: `cluster/apps/authentik-system/authentik/app/external-secrets-rbac.yaml` (MODIFY)

Add new Role + RoleBinding for vaultwarden:

- Role: `vaultwarden-oauth-reader` (read `authentik-vaultwarden-oauth`)
- RoleBinding: bind to SA `authentik-secret-reader` in `vaultwarden` namespace

### 2.7 User: Add SSO Config to Vaultwarden Secret

**File**: `cluster/apps/vaultwarden/vaultwarden/app/vaultwarden-secrets.sops.yaml` (USER EDITS MANUALLY)

User will add SSO config vars (NOT credentials - those come from ExternalSecret):

```yaml
SSO_ENABLED: "true"
SSO_AUTHORITY: "https://auth.spruyt.xyz/application/o/vaultwarden/" # Trailing slash REQUIRED for Authentik
SSO_SCOPES: "openid email profile offline_access"
SSO_PKCE: "true"
SSO_SIGNUPS_MATCH_EMAIL: "true"
SSO_DEBUG_TOKENS: "true" # Remove after SSO working
```

### 2.8 Update Vaultwarden Values

**File**: `cluster/apps/vaultwarden/vaultwarden/app/values.yaml` (MODIFY)

Add second envFrom to load OAuth credentials from ExternalSecret:

```yaml
envFrom:
  - secretRef:
      name: vaultwarden-secrets
  - secretRef:
      name: vaultwarden-oauth-credentials # From ExternalSecret
```

### 2.9 Update Vaultwarden Kustomization

**File**: `cluster/apps/vaultwarden/vaultwarden/app/kustomization.yaml` (MODIFY)

Add resources:

- `./authentik-secret-store.yaml`
- `./vaultwarden-oauth-external-secret.yaml`

### 2.10 Add Vaultwarden to Rotation CronJob

**File**: `cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/cronjob.yaml` (MODIFY)

Add section for Vaultwarden rotation:

- Find provider ID for "Vaultwarden"
- Update credentials via API
- Patch `authentik-vaultwarden-oauth` secret
- Force ExternalSecret sync for vaultwarden namespace

**File**: `cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/role.yaml` (MODIFY)

Add permission to patch `authentik-vaultwarden-oauth` secret

---

## Phase 3: Update Documentation

### 3.1 Update CLAUDE.md - Context7 Usage

**File**: `CLAUDE.md`

Strengthen Context7 section:

```markdown
## Context7

- **ALWAYS use Context7 BEFORE web search** for library/tool documentation
- Auto-fetch docs for common tools (Flux, Kubernetes, Helm, Cilium, Traefik, Rook, etc.)
- Ask before resolving unfamiliar/niche libraries
- Match cluster versions when available
```

### 3.2 Update Authentik README

**File**: `cluster/apps/authentik-system/authentik/README.md`

Add sections based on learnings:

- Complete file list for adding SSO to a new app
- Cross-namespace secret sync pattern (ExternalSecret + SecretStore)
- RBAC requirements in authentik-system
- App-specific config examples (Grafana vs Vaultwarden patterns)

---

## Files Summary

| File                                                                                | Action                         | Who         |
| ----------------------------------------------------------------------------------- | ------------------------------ | ----------- |
| **Phase 1 - Test Image**                                                            |                                |             |
| `cluster/apps/vaultwarden/vaultwarden/app/values.yaml`                              | Change tag to `testing-alpine` | Claude      |
| **Phase 2 - Authentik Side**                                                        |                                |             |
| `cluster/apps/authentik-system/authentik/app/blueprints/vaultwarden-sso.yaml`       | CREATE                         | Claude      |
| `cluster/apps/authentik-system/authentik/app/authentik-vaultwarden-oauth.sops.yaml` | CREATE                         | User (SOPS) |
| `cluster/apps/authentik-system/authentik/app/kustomization.yaml`                    | Add new files                  | Claude      |
| `cluster/apps/authentik-system/authentik/app/values.yaml`                           | Add env vars                   | Claude      |
| `cluster/apps/authentik-system/authentik/app/external-secrets-rbac.yaml`            | Add vaultwarden RBAC           | Claude      |
| `cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/cronjob.yaml`    | Add vaultwarden rotation       | Claude      |
| `cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/role.yaml`       | Add secret permission          | Claude      |
| **Phase 2 - Vaultwarden Side**                                                      |                                |             |
| `cluster/apps/vaultwarden/vaultwarden/app/authentik-secret-store.yaml`              | CREATE                         | Claude      |
| `cluster/apps/vaultwarden/vaultwarden/app/vaultwarden-oauth-external-secret.yaml`   | CREATE                         | Claude      |
| `cluster/apps/vaultwarden/vaultwarden/app/kustomization.yaml`                       | Add new files                  | Claude      |
| `cluster/apps/vaultwarden/vaultwarden/app/values.yaml`                              | Add envFrom                    | Claude      |
| `cluster/apps/vaultwarden/vaultwarden/app/vaultwarden-secrets.sops.yaml`            | Add SSO config vars            | User (SOPS) |
| **Phase 3 - Documentation**                                                         |                                |             |
| `CLAUDE.md`                                                                         | Strengthen Context7 section    | Claude      |
| `cluster/apps/authentik-system/authentik/README.md`                                 | Add SSO onboarding guide       | Claude      |

---

## Reference: Vaultwarden SSO Env Vars (from Context7 + GitHub #6450)

| Variable                  | Value                                                        | Notes                                              |
| ------------------------- | ------------------------------------------------------------ | -------------------------------------------------- |
| `SSO_ENABLED`             | `true`                                                       | Required                                           |
| `SSO_AUTHORITY`           | `https://auth.${EXTERNAL_DOMAIN}/application/o/vaultwarden/` | Trailing slash REQUIRED                            |
| `SSO_CLIENT_ID`           | From secret                                                  | Must match Authentik provider                      |
| `SSO_CLIENT_SECRET`       | From secret                                                  | Must match Authentik provider                      |
| `SSO_SCOPES`              | `openid email profile offline_access`                        | Include offline_access for refresh                 |
| `SSO_PKCE`                | `true`                                                       | Default, recommended                               |
| `SSO_SIGNUPS_MATCH_EMAIL` | `true`                                                       | Link existing users by email                       |
| `SSO_DEBUG_TOKENS`        | `true`                                                       | **Temporary** - enable during setup, disable after |

**Callback URL for Authentik**: `https://vaultwarden.${EXTERNAL_DOMAIN}/identity/connect/oidc-signin`

## Debugging Tips (from GitHub #6450 + Wiki)

1. **"invalid_client" error**: Credentials mismatch between Vaultwarden and Authentik
2. Enable `SSO_DEBUG_TOKENS=true` temporarily to see token exchange logs
3. Verify callback URL matches exactly (no trailing slashes, correct path)
4. Check Authentik logs for authorization success but token failure

**Authentik-Specific Issues:**

- **"Failed to discover OpenID provider"**: Test `https://auth.spruyt.xyz/application/o/vaultwarden/.well-known/openid-configuration` is reachable
- **HS256 error**: Re-select the default signing key in Authentik provider settings (must be RS256)
- **"Invalid JSON web token: found 5 parts"**: Encryption enabled - ensure no encryption key is set in Authentik
- **Token expiry issues**: Set access_token_validity > 5 min in Authentik provider (Applications → Providers → Edit → Advanced protocol settings)
