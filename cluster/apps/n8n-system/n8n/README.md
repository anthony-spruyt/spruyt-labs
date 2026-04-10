# n8n - Workflow Automation

## Overview

n8n is a workflow automation tool that connects various applications and services through visual workflows. It provides a low-code platform for integrating APIs, databases, and cloud services in the spruyt-labs homelab infrastructure, enabling powerful automation capabilities.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- CNPG operator deployed (dependency)
- Barman Cloud plugin deployed (dependency)
- Authentik deployed (dependency)
- Valkey deployed (dependency)
- Claude agents write deployed (dependency)

## Operation

### Procedures

1. **Workflow management**:

   - Access n8n web interface at `https://n8n.${EXTERNAL_DOMAIN}`
   - Create and manage workflows
   - Monitor workflow execution

2. **Database operations** - See [CNPG operator docs](../../cnpg-system/cnpg-operator/README.md#kubectl-cnpg-plugin) for `kubectl cnpg` plugin usage. Cluster name: `n8n-cnpg-cluster`

   ```bash
   # Check connection pooler status
   kubectl get poolers -n n8n-system

   # Verify scheduled backups
   kubectl get scheduledbackups -n n8n-system
   ```

3. **Performance monitoring**:

   ```bash
   # Check n8n service status
   kubectl get pods -n n8n-system

   # Monitor resource usage
   kubectl top pods -n n8n-system
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate workflow management
kubectl get pods -n n8n-system --no-headers | grep 'Running'

# Expected: n8n pods running

# Validate database monitoring
kubectl get poolers -n n8n-system

# Expected: Connection poolers listed

# Validate performance monitoring
kubectl top pods -n n8n-system

# Expected: Resource usage displayed
```

## Troubleshooting

### Common Issues

1. **Database connection failures**:

   - **Symptom**: Pods stuck in CrashLoopBackOff
   - **Diagnosis**: Check CNPG cluster health and connection details
   - **Resolution**: Verify PostgreSQL credentials and network connectivity

2. **Workflow execution errors**:

   - **Symptom**: Workflows failing to execute
   - **Diagnosis**: Check n8n logs and workflow configuration
   - **Resolution**: Verify workflow syntax and API connections

3. **Resource constraints**:

   - **Symptom**: Pods in Pending state or frequent restarts
   - **Diagnosis**: Check resource requests vs available cluster resources
   - **Resolution**: Adjust resource limits or scale cluster

4. **Network connectivity issues**:

   - **Symptom**: External API connections failing
   - **Diagnosis**: Check network policies and egress connectivity
   - **Resolution**: Verify network configuration and firewall rules

## SSO Authentication

N8N Community Edition doesn't support OAuth2 natively. SSO is implemented via Authentik's Proxy Provider with forward-auth and external hooks.

### How It Works

1. User navigates to `https://n8n.${EXTERNAL_DOMAIN}`
2. Traefik's forwardAuth middleware calls Authentik's standalone outpost
3. Authentik authenticates user and injects `X-authentik-email` header
4. N8N's external hooks (`hooks.js`) read the header and issue a session cookie
5. User is logged in with their pre-provisioned N8N account

### User Provisioning

**Users must be pre-provisioned in N8N before SSO login works.** The hooks script looks up users by email - if not found, returns 401.

To add a user:

1. Log in to N8N as admin
2. Go to Settings > Users
3. Invite user with their Authentik email address

### MFA Considerations

If a user has MFA enabled in N8N, it should be disabled for SSO users since authentication is handled by Authentik:

```bash
kubectl exec -n n8n-system deploy/n8n -- n8n mfa:disable --email=user@example.com
```

MFA at the Authentik level is recommended instead for SSO users.

### Webhook Bypass

Webhooks are excluded from SSO authentication to allow external integrations:

- `/webhook/*` - Production webhooks
- `/webhook-test/*` - Test webhooks
- `/healthz` - Health checks

## Unified SRE Workflow

n8n hosts a unified SRE workflow that combines alert triage and scheduled health checks. Each agent has a dedicated MCP tool (`submit_alert_triage` / `submit_health_check_triage`) which validates the schema and posts to Discord. The health check agent only calls its tool when issues are found.

### Triggers

| Trigger | Source | Agent |
| ------- | ------ | ----- |
| Alertmanager Webhook | Firing alerts (filtered: Watchdog, InfoInhibitor, resolved) | SRE triage |
| Cron (6h) | Scheduled | Health check |
| MCP Server Trigger | Agent `submit_alert_triage` / `submit_health_check_triage` call | Result processing |

### Authentication

| Endpoint | Credential |
| -------- | ---------- |
| Alertmanager Webhook | `Alertmanager webhook for SRE agent` (headerAuth) |
| MCP Server Trigger | `SRE Agent MCP auth` (headerAuth) |

### Agent Configuration

- **Model:** `claude-opus-4-6`
- **Connection mode:** `k8sEphemeral`
- **MCP config:** `/etc/mcp/mcp.json` (includes SRE MCP server for `submit_alert_triage` / `submit_health_check_triage`)

See `docs/sre-automation/sre.md` for the full architecture and investigation flow.

### Configuration Files

| Component       | Location                      |
| --------------- | ----------------------------- |
| Hooks ConfigMap | `app/hooks-configmap.yaml`    |
| Values (env)    | `app/values.yaml`             |
| Ingress Routes  | `traefik/ingress/n8n-system/` |

See [Authentik README](../../authentik-system/authentik/README.md#adding-sso-via-proxy-provider-forward-auth) for the complete SSO integration pattern.

## Maintenance

### Updates

```bash
# Update n8n using Flux
flux reconcile kustomization n8n --with-source
```

### Backup Management

```bash
# Verify scheduled backups
kubectl get scheduledbackups -n n8n-system

# Check backup status
kubectl get backups -n n8n-system
```

## References

- [n8n Documentation](https://docs.n8n.io/)
- [n8n API Documentation](https://docs.n8n.io/api/)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [CloudNative-PG Documentation](https://cloudnative-pg.io/)
