# Technitium - DNS Server

## Overview

Technitium is a powerful, open-source DNS server that provides authoritative DNS services. In the spruyt-labs homelab infrastructure, Technitium serves as the primary DNS server for internal domain resolution, providing reliable and configurable DNS services for the homelab environment.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Persistent storage for DNS zone data
- Network connectivity for DNS traffic (UDP/TCP port 53)
- Proper RBAC permissions for DNS operations
- TLS certificates for secure DNS operations
- Authentik OIDC provider configured (blueprint: `technitium-sso.yaml`)

## Operation

### Procedures

1. **DNS zone management**:

   DNS zones are managed through the Technitium web UI or its HTTP API. Access the web interface to view and manage zones.

   ```bash
   # Monitor DNS queries
   kubectl logs -n technitium <technitium-pod> | grep "query"
   ```

1. **Performance monitoring**:

   ```bash
   # Check DNS performance
   kubectl top pods -n technitium

   # Monitor response times
   kubectl logs -n technitium <technitium-pod> | grep "response"
   ```

1. **Configuration updates**:

   ```bash
   # Update Technitium configuration
   # Edit values.yaml, commit, then: flux reconcile kustomization technitium --with-source

   # Restart pods for configuration changes
   kubectl rollout restart deployment technitium -n technitium
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate DNS zone management
# Use the Technitium web UI or HTTP API to verify zones

# Validate performance monitoring
kubectl top pods -n technitium

# Expected: Resource usage displayed

# Validate configuration updates
kubectl get pods -n technitium --no-headers | grep 'Running'

# Expected: Pods running after restart
```

## Single Sign-On (SSO)

Technitium v15+ supports OIDC SSO via Authentik. Both primary and secondary instances share a single Authentik OIDC provider with separate redirect URIs.

### Architecture

```text
Browser → Technitium UI → Authentik (auth.${EXTERNAL_DOMAIN}) → OIDC callback → Technitium
```

- **Authentik provider**: `Technitium` (blueprint-managed)
- **Redirect URIs**: `https://dns.lan.${EXTERNAL_DOMAIN}:53443/sso/callback`, `https://dns-secondary.lan.${EXTERNAL_DOMAIN}:53443/sso/callback`
- **Access control**: Authentik `Technitium Users` group
- **ExternalSecret**: Syncs OIDC credentials from `authentik-system` → `technitium` namespace

### Important: Config Persistence

Technitium reads environment variables **only on first startup**. After that, config is persisted to PVC and env vars are ignored. This means:

- SSO must be configured via the **Technitium admin UI** (Settings → SSO) on each instance
- Env vars in `values.yaml` serve as fallback for fresh PVC provisioning only
- If the PVC is deleted/recreated, SSO will auto-configure from env vars on first boot

### Secret Rotation: NOT Automated

Technitium is **excluded** from the weekly `oauth-secret-rotation` CronJob because:

1. Rotation updates Authentik + K8s secrets, then Reloader restarts the pod
1. Technitium ignores env vars on restart, reads old secret from PVC
1. Result: Authentik has new secret, Technitium has old → SSO breaks

**To manually rotate the Technitium OIDC client secret:**

1. Generate a new secret
1. Update the Authentik provider via API or admin UI
1. Update the `authentik-technitium-oauth` secret in `authentik-system` namespace
1. Update SSO settings in **both** Technitium instances via their admin UIs
1. Verify SSO login works on both instances

### Troubleshooting SSO

1. **SSO button not appearing**:

   - SSO must be enabled via Technitium admin UI, not just env vars
   - Verify Settings → SSO → "Enable Single Sign-On" is checked

1. **SSO login fails with redirect error**:

   - Verify redirect URI in Authentik matches exactly: `https://dns.lan.${EXTERNAL_DOMAIN}:53443/sso/callback`
   - Check Authentik provider has both redirect URIs (primary + secondary)

1. **SSO login fails with invalid client**:

   - Client secret may have been rotated — check current value in `technitium-oauth-credentials` secret matches what Technitium has in its config
   - Re-enter credentials in Technitium UI if needed

## Troubleshooting

### Common Issues

1. **DNS resolution failures**:

   - **Symptom**: DNS queries failing or timing out
   - **Diagnosis**: Check DNS logs and zone configuration
   - **Resolution**: Verify zone files and DNS records

1. **Zone transfer problems**:

   - **Symptom**: Zone transfer failures
   - **Diagnosis**: Check zone transfer logs
   - **Resolution**: Verify zone transfer configuration

1. **Performance bottlenecks**:

   - **Symptom**: High DNS query latency
   - **Diagnosis**: Monitor DNS performance metrics
   - **Resolution**: Scale resources or optimize DNS configuration

1. **TLS certificate issues**:

   - **Symptom**: DNS-over-TLS failures
   - **Diagnosis**: Check certificate status
   - **Resolution**: Verify cert-manager certificate configuration

## Maintenance

### Updates

```bash
# Update Technitium using Flux
flux reconcile kustomization technitium --with-source

# Check update status
flux get hr -n technitium technitium
```

### Zone Management

DNS zones are managed through the Technitium web UI or its HTTP API. There is no CLI tool for Technitium zone management.

## References

- [Technitium Documentation](https://technitium.com/dns/)
- [DNS Protocol Reference](https://www.rfc-editor.org/rfc/rfc1035)
- [Kubernetes DNS Guide](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [DNS Security Best Practices](https://www.ietf.org/rfc/rfc2845.txt)
