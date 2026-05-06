# Firefly III - Personal Finance Manager

## Overview

Firefly III is a free and open-source personal finance manager that helps track expenses, income, and budgets. Deployed with CNPG PostgreSQL database, Authentik SSO via forward-auth, and external ingress.

**Priority Tier**: `standard` - Business application with availability expectations (3x CPU limit policy)

## Prerequisites

- authentik (SSO provider)
- cnpg-operator (PostgreSQL database operator)
- plugin-barman-cloud (CNPG backup plugin)

## Architecture

```text
Internet → Traefik → Authentik Outpost → Firefly III → CNPG PostgreSQL
                      (forward-auth)         ↓              ↓
                                         ff3-ofx      Barman S3 Backups
                                        (static)
```

## Plugins

### ff3-ofx (OFX Bank Import)

[ff3-ofx](https://github.com/pelaxa/ff3-ofx) is a React application for importing bank statements in OFX format. It runs client-side and uses the Firefly III API.

**Access**: `https://firefly.${EXTERNAL_DOMAIN}/ofx`

**How it works**:

- Static files downloaded via init container from GitHub releases
- Mounted at `/var/www/html/public/ofx` (served by Apache)
- Uses Personal Access Token (PAT) stored in browser localStorage
- No Authentik SSO integration (manages its own PAT auth)

**Setup**:

1. Navigate to `https://firefly.${EXTERNAL_DOMAIN}/ofx`
1. Create PAT in Firefly III: Options → Profile → OAuth → Create Token
1. Enter PAT in ff3-ofx login prompt
1. Optionally check "Store token for next time"

## Authentication

Firefly III uses header-based authentication via Authentik forward-auth with a **shared household email** for multi-user access to the same financial data.

### How It Works

1. User accesses `https://firefly.${EXTERNAL_DOMAIN}`
1. Traefik forwards request to Authentik outpost for authentication
1. Authentik validates session and injects `X-Firefly-Household-Email: household@firefly.local` header
1. Firefly III reads email from header and logs in as the shared household user

### Shared Household Finance

Since Firefly III doesn't natively support multiple users managing shared finances, we use a custom Authentik scope mapping to make all authorized users appear as the same Firefly III user:

- **Header**: `X-Firefly-Household-Email`
- **Value**: `household@firefly.local` (static for all users)
- **Effect**: All family members in the "Firefly III Users" group share one Firefly III account

This allows multiple people to manage household finances without needing Firefly III's planned (post-6.0) multi-user feature.

### Configuration Components

| Component              | Location                                                         |
| ---------------------- | ---------------------------------------------------------------- |
| Authentik blueprint    | `authentik-system/authentik/app/blueprints/firefly-iii-sso.yaml` |
| Scope mapping          | `firefly_iii_shared_email_scope` (in blueprint)                  |
| Traefik header patch   | `traefik/traefik/ingress/firefly-iii/kustomization.yaml`         |
| Firefly III auth guard | `AUTHENTICATION_GUARD_HEADER: HTTP_X_FIREFLY_HOUSEHOLD_EMAIL`    |

**Note**: Traefik requires custom headers to be explicitly listed in `authResponseHeaders` - see Authentik README for details.

### Access Control

Users must be added to the "Firefly III Users" group in Authentik to access the application.

## Troubleshooting

### Common Issues

1. **User cannot log in via SSO**

   - **Symptom**: 403 Forbidden or redirect loop
   - **Resolution**: Verify user is in "Firefly III Users" group in Authentik Admin UI

1. **Blueprint not applied**

   - **Symptom**: Application doesn't appear in Authentik
   - **Resolution**: Check blueprint status:
     ```bash
     kubectl exec -n authentik-system deploy/authentik-server -- ak shell -c \
       "from authentik.blueprints.models import BlueprintInstance; \
        [print(f'{b.name} - {b.status}') for b in BlueprintInstance.objects.filter(name__icontains='firefly')]"
     ```

1. **Database connection failed**

   - **Symptom**: Pod crashes with database connection error
   - **Resolution**: Verify CNPG cluster is ready and secrets exist:
     ```bash
     kubectl get cluster -n firefly-iii
     kubectl get secret -n firefly-iii firefly-iii-cnpg-cluster-app
     ```

1. **Outpost not deployed**

   - **Symptom**: 503 Service Unavailable on auth path
   - **Resolution**: Check Authentik outpost RBAC and logs:
     ```bash
     kubectl get role,rolebinding -n firefly-iii
     kubectl logs -n authentik-system deploy/authentik-worker --tail=50
     ```

## References

- [Firefly III Documentation](https://docs.firefly-iii.org/)
- [Firefly III Kubernetes Helm Chart](https://github.com/firefly-iii/kubernetes)
- [CloudNative-PG Documentation](https://cloudnative-pg.io/documentation/)
