# Headlamp - Kubernetes Dashboard

## Overview

LAN-only Kubernetes UI (with Flux and cert-manager plugins) where users act **as themselves** against the API server: Headlamp passes the user's Authentik OIDC token to kube-apiserver, which validates it directly. It is the only app here that needs kube-apiserver OIDC, and that requirement drives most of the setup below.

## Prerequisites

- kube-apiserver OIDC in `talos/patches/control-plane/05-configure-api-server.yaml.tpl` (a `KubeAuthenticationConfig`). Its audience is `HEADLAMP_OIDC_CLIENT_ID`, read from `talos/talenv.sops.yaml` via `talos/topf.yaml`. A Talos config apply is needed after changing either.
- The same client ID in `authentik-system/authentik/app/authentik-headlamp-oauth.sops.yaml`. The two copies must match, which is why Headlamp's `client_id` is never rotated.
- Authentik blueprint `authentik-system/authentik/app/blueprints/headlamp-sso.yaml`.

## Operations

### How authentication works

1. Headlamp authenticates the user against Authentik (OIDC, RS256).
2. The ID token is sent to kube-apiserver, which accepts issuer `https://auth.${EXTERNAL_DOMAIN}/application/o/headlamp/` with the Headlamp client ID as audience.
3. The username is the `email` claim with no prefix, so RBAC subjects are plain email addresses. `app/user-rbac.yaml` binds `${MY_AUTHENTIK_USER_EMAIL}` to `cluster-admin`; add a subject there for each additional user.

The Talos patch replaces Talos' generated `AuthenticationConfiguration` wholesale, which is why it also restates anonymous access to `/livez`, `/readyz` and `/healthz`. Dropping that block breaks the API server's own probes.

### email_verified claim

kube-apiserver rejects tokens with `email_verified: false`, and Authentik (v2025.10+) always returns `false` because it has no email verification. The Headlamp blueprint replaces the default email scope mapping with one that returns `email_verified: true`. This is acceptable because access requires membership in `Headlamp Users` (policy binding) and the claim carries no real verification in
Authentik anyway. Pattern details are in the [authentik README](../../authentik-system/authentik/README.md#email_verified-claim).

### OIDC config comes from one secret

The chart's `externalSecret` mode expects **all** OIDC settings in the secret, so `app/headlamp-oauth-external-secret.yaml` templates issuer, scopes and callback URL alongside the synced client ID and secret. It writes each value twice: `OIDC_*` for the chart's `envFrom`, and `HEADLAMP_CONFIG_OIDC_*` for Headlamp's own config loader, which keeps the client secret off the command line
(`/proc/<pid>/cmdline`).

Client-secret rotation follows the shared Authentik rotation job; see the [authentik README](../../authentik-system/authentik/README.md#oauth-credential-rotation).

### Plugins

Plugins install at startup through the chart's `pluginsManager`. Entries must use the ArtifactHub name (e.g. `headlamp_flux`, no `@org/` npm scope) and an `https://artifacthub.io/packages/headlamp/<repo>/<plugin>` source; npm names or npmjs URLs fail schema validation. Each entry has a `# renovate: depName=` line so Renovate can bump its version.

## Troubleshooting

1. **Login succeeds but every API call is 401**

   - **Cause**: kube-apiserver rejected the token. Usually `email_verified: false` (the custom email mapping is missing from the blueprint) or a client ID mismatch between the Talos patch and the Authentik secret.
   - **Fix**: Check the kube-apiserver logs for the rejection reason; fix the blueprint or re-align the client ID and apply the Talos config.

2. **Login succeeds but resources are forbidden**

   - **Cause**: The user's email has no RBAC binding.
   - **Fix**: Add a `User` subject with that exact email to `app/user-rbac.yaml`.

3. **Plugin install fails with `name must match pattern` or `source must match pattern`**

   - **Cause**: npm-style name or source.
   - **Fix**: Use the ArtifactHub name and URL.

4. **Kubeconfig errors in the logs**

   - Expected in-cluster; Headlamp looks for kubeconfig files before falling back to the service account.

## References

- [Headlamp Documentation](https://headlamp.dev/docs/latest/)
- [Kubernetes structured authentication configuration](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#using-authentication-configuration)
