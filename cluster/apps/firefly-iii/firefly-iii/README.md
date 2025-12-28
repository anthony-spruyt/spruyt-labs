# Firefly III - Personal Finance Manager

## Overview

Firefly III is a free and open-source personal finance manager that helps track expenses, income, and budgets. Deployed with CNPG PostgreSQL database, Authentik SSO via forward-auth, and external ingress.

**Priority Tier**: `standard` - Business application with availability expectations (3x CPU limit policy)

> **Note**: HelmRelease resources are managed by Flux in flux-system namespace but deploy workloads to the firefly-iii namespace specified in ks.yaml.

## Prerequisites

- Kubernetes cluster with Flux CD
- authentik (SSO provider)
- cnpg-operator (PostgreSQL database operator)
- plugin-barman-cloud (CNPG backup plugin)

## Architecture

```text
Internet → Traefik → Authentik Outpost → Firefly III → CNPG PostgreSQL
                      (forward-auth)                        ↓
                                                     Barman S3 Backups
```

## Authentication

Firefly III uses header-based authentication via Authentik forward-auth:

1. User accesses `https://firefly.${EXTERNAL_DOMAIN}`
2. Traefik forwards request to Authentik outpost for authentication
3. Authentik validates session and sets `X-authentik-email` header
4. Firefly III reads email from header and auto-creates/logs in user

Users must be added to the "Firefly III Users" group in Authentik.

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n firefly-iii
flux get helmrelease -n flux-system firefly-iii

# Check CNPG database
kubectl get cluster -n firefly-iii
kubectl get pod -n firefly-iii -l cnpg.io/cluster=firefly-iii-cnpg-cluster

# Check Authentik outpost
kubectl get deploy -n firefly-iii -l app.kubernetes.io/name=ak-outpost-firefly-iii-outpost

# Force reconcile (GitOps approach)
flux reconcile kustomization firefly-iii --with-source

# View logs
kubectl logs -n firefly-iii -l app.kubernetes.io/name=firefly-iii --tail=50
```

### Database Operations

```bash
# Check database cluster health
kubectl get cluster -n firefly-iii firefly-iii-cnpg-cluster

# View database logs
kubectl logs -n firefly-iii -l cnpg.io/cluster=firefly-iii-cnpg-cluster --tail=50

# Check backup status
kubectl get backups -n firefly-iii
kubectl get scheduledbackups -n firefly-iii
```

## Troubleshooting

### Common Issues

1. **User cannot log in via SSO**
   - **Symptom**: 403 Forbidden or redirect loop
   - **Resolution**: Verify user is in "Firefly III Users" group in Authentik Admin UI

2. **Blueprint not applied**
   - **Symptom**: Application doesn't appear in Authentik
   - **Resolution**: Check blueprint status:
     ```bash
     kubectl exec -n authentik-system deploy/authentik-server -- ak shell -c \
       "from authentik.blueprints.models import BlueprintInstance; \
        [print(f'{b.name} - {b.status}') for b in BlueprintInstance.objects.filter(name__icontains='firefly')]"
     ```

3. **Database connection failed**
   - **Symptom**: Pod crashes with database connection error
   - **Resolution**: Verify CNPG cluster is ready and secrets exist:
     ```bash
     kubectl get cluster -n firefly-iii
     kubectl get secret -n firefly-iii firefly-iii-cnpg-cluster-app
     ```

4. **Outpost not deployed**
   - **Symptom**: 503 Service Unavailable on auth path
   - **Resolution**: Check Authentik outpost RBAC and logs:
     ```bash
     kubectl get role,rolebinding -n firefly-iii
     kubectl logs -n authentik-system deploy/authentik-worker --tail=50
     ```

## References

- [Firefly III Documentation](https://docs.firefly-iii.org/)
- [Firefly III Kubernetes Helm Chart](https://github.com/firefly-iii/kubernetes)
- [CNPG Documentation](https://cloudnative-pg.io/documentation/)
- [Authentik Forward Auth Documentation](https://goauthentik.io/docs/providers/proxy/)
