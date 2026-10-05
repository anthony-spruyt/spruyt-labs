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

`app/plugins/traefik-api-key-auth/` is vendored source for [LinkPhoenix/traefik-api-key-auth](https://github.com/LinkPhoenix/traefik-api-key-auth), loaded as a local plugin from a ConfigMap. It is vendored because the upstream module is not in the Traefik plugin catalog, so a remote plugin reference fails to download and every route using it returns 404. The local copy also adds a passthrough mode
(`forwardBearerHeader` with no `keys`) that translates `X-API-KEY` into `Authorization: Bearer` for backends that validate the token themselves. It has its own Go tests, run in CI.

Current consumer: `api-key-auth-otel` on the `otel.lan` OTLP route in `ingress/observability/`, keyed from `OTEL_API_KEY` in `app/api-keys-secrets.sops.yaml`.

### Security settings worth keeping

- `aliasHeadersStrategy: delete` on every entry point mitigates GHSA-rf44-j88r-hh8c, where clients spoof ForwardAuth identity headers (`X-authentik-*`) with underscore/dot aliases. Keep it on any new entry point.
- `forwardedHeaders.trustedIPs` trusts only the pod CIDR (cloudflared), so `X-Forwarded-*` from LAN clients are discarded.

### Other wiring

`app/coder-service-reader-rbac.yaml` lets the Coder provisioner read the `traefik` Service to put its LB IP into workspace `hostAliases`.

## References

- [Traefik Kubernetes CRD routing](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/crd/http/ingressroute/)
