# hubble-sso - Hubble UI Forward-Auth

## Overview

RBAC that lets Authentik deploy its proxy outpost into `kube-system`, putting Hubble UI (which has no auth of its own) behind Authentik forward-auth. The rest of the wiring lives elsewhere:

| Piece                            | Location                                                    |
| -------------------------------- | ----------------------------------------------------------- |
| Provider, app, group, outpost    | `authentik-system/authentik/app/blueprints/hubble-sso.yaml` |
| Outpost route + forward-auth     | `traefik/traefik/ingress/kube-system/`                      |
| Outpost deployer Role (this app) | `rbac/authentik-outpost-rbac.yaml`                          |

The procedure is the proxy-provider flow in the [authentik README](../../authentik-system/authentik/README.md). Unlike `flux-sso`, no NetworkPolicy is needed here because `kube-system` has no default-deny.
