# Traefik - Ingress Controller

## Overview

Single ingress controller for LAN (`*.lan.${EXTERNAL_DOMAIN}`) and public traffic; the Cloudflare tunnel forwards public hostnames here. All routes are Traefik `IngressRoute` CRDs kept under `ingress/`, not in each app.

## Operations

### Adding a route

The IngressRoute/Certificate pattern and DNS annotations are in [`.claude/rules/ingress-and-certificates.md`](../../../../.claude/rules/ingress-and-certificates.md). Beyond that:

- `ingress/<namespace>/` holds one kustomization per target namespace, pulling the shared middlewares from `ingress/base/` and patching their namespace. Copy an existing directory (`whoami` is the smallest).
- Add the app's Kustomization to `traefik-ingress`'s `dependsOn` in `ks.yaml`, otherwise the route can reconcile before its backend Service exists.

Middlewares must live in the route's namespace because `allowCrossNamespace: false`; that is why each directory patches its own copy of `lan-ip-whitelist`, `compress` and friends. SSO wiring (`authentik-forward-auth`, `https-proto-header`) is covered in the [authentik README](../../authentik-system/authentik/README.md).

To block part of a host, add a higher-`priority` route matching it with the `deny-all` middleware (403). The route still needs a real `services` entry, which never gets called. Example: WebSocket upgrades in `ingress/litellm/`.

### Local plugin: traefik-api-key-auth

The plugin source lives in [anthony-spruyt/traefik-api-key-auth](https://github.com/anthony-spruyt/traefik-api-key-auth), our fork of LinkPhoenix's plugin with a passthrough mode (`forwardBearerHeader` with no `keys`) that translates `X-API-KEY` into `Authorization: Bearer` for backends that validate the token themselves. It ships as a source-only OCI image, mounted as an image volume under
`/plugins-local` and loaded as a local plugin, so Traefik downloads nothing at startup. The `localPlugins` key, `traefik-api-key-auth`, must match the `plugin:` key in every Middleware.

If the plugin fails to load, Traefik still starts (`abortOnPluginFailure` is off) but drops every Middleware that uses it, and routes referencing those Middlewares return 404. Check the Traefik logs for `Plugins are disabled because an error has occurred`.

Current consumer: `api-key-auth-otel` on the `otel.lan` OTLP route in `ingress/observability/`, keyed from `OTEL_API_KEY` in the ESO-generated `traefik-otel-api-key` secret (`app/otel-api-key-eso.yaml`). The key is `sl_` plus alphanumerics so LiteLLM secret masking catches it if it ever lands in a prompt. To rotate it, delete both the Secret and the ExternalSecret
(`kubectl -n traefik delete secret,externalsecret traefik-otel-api-key`); Flux recreates the ExternalSecret with a new key. Then `kubectl -n traefik rollout restart deploy/traefik`, since nothing rolls Traefik on its own. Then update `OTEL_EXPORTER_OTLP_HEADERS` on every devcontainer host (see `DEVELOPMENT.md`). In-cluster senders go straight to backend pod DNS and don't use the key.

### Security settings worth keeping

- `aliasHeadersStrategy: delete` on every entry point mitigates GHSA-rf44-j88r-hh8c, where clients spoof ForwardAuth identity headers (`X-authentik-*`) with underscore/dot aliases. Keep it on any new entry point.
- `forwardedHeaders.trustedIPs` trusts only the pod CIDR (cloudflared), so `X-Forwarded-*` from LAN clients are discarded.
- `lan-ip-whitelist` alone does not keep a public hostname's path LAN-only: cloudflared runs in-cluster, so tunnel traffic arrives from an allowed pod IP. Add a `deny-all` route for that path that also matches `` HeaderRegexp(`Cf-Connecting-Ip`, `.+`) ``, a header only tunnel requests carry. Example: the admin path in `ingress/vaultwarden/`. This only works when LAN DNS resolves the host to
  Traefik; `auth` resolves through Cloudflare on the LAN too (#1856), so the header can't tell LAN from internet there.

### Other wiring

`app/coder-service-reader-rbac.yaml` lets the Coder provisioner read the `traefik` Service to put its LB IP into workspace `hostAliases`.

## References

- [Traefik Kubernetes CRD routing](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/crd/http/ingressroute/)
