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

### Adding SSO Integration (Blueprints)

1. Create blueprint in `app/blueprints/<app>.yaml` (use schema in file)
2. Add credentials to `app/authentik-secrets.sops.yaml`
3. Add file to `app/kustomization.yaml` configMapGenerator
4. Add env vars to `app/values.yaml`

Required OAuth2Provider fields (2025.10+): `authorization_flow`, `invalidation_flow`

### Debugging Blueprint Errors

```bash
kubectl exec -n authentik-system deploy/authentik-server -- ak shell -c "
from authentik.blueprints.v1.importer import Importer
from authentik.blueprints.models import BlueprintInstance
bp = BlueprintInstance.objects.filter(name='Name').first()
print(Importer.from_string(bp.retrieve(), bp.context).apply())
"
```

## Troubleshooting

1. **Blueprint shows error but no logs** - Errors stored in DB, use debug command above
2. **Database connection failures** - Check CNPG cluster health
3. **Pods CrashLoopBackOff** - Check secrets and Redis connectivity

## References

- [authentik Documentation](https://goauthentik.io/docs/)
- [Blueprint Schema](https://raw.githubusercontent.com/goauthentik/authentik/refs/heads/main/blueprints/schema.json)
