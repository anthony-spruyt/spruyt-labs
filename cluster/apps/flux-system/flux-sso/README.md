# flux-sso - Flux Operator UI Forward-Auth

## Overview

Lets Authentik deploy its proxy outpost into `flux-system` so the flux-operator web UI sits behind Authentik forward-auth. Blueprint: `authentik-system/authentik/app/blueprints/flux-sso.yaml`; route: `traefik/traefik/ingress/flux-system/`. The procedure is the proxy-provider flow in the [authentik README](../../authentik-system/authentik/README.md).

## Operations

`rbac/outpost-networkpolicy.yaml` is required, not optional. flux-operator generates NetworkPolicies for `flux-system` that only admit the ports Flux itself uses, so without this policy Traefik cannot reach the outpost on 9000 and every SSO login times out.
