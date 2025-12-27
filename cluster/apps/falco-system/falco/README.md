# Falco - Runtime Security Monitoring

## Overview

Falco is a cloud-native runtime security tool that monitors system calls to detect anomalous behavior and potential threats. Deployed as high-priority (Tier 2) security observability infrastructure.

Components:

- **Falco** - DaemonSet monitoring syscalls on all nodes via modern_ebpf driver
- **Falcosidekick** - Alert forwarder to VictoriaLogs

> **Note**: HelmRelease resources are managed by Flux in flux-system namespace but deploy workloads to falco-system.

## Prerequisites

- Kubernetes cluster with Flux CD
- Talos Linux with `lockdown=integrity` kernel arg (required for modern_ebpf driver)

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n falco-system
flux get helmrelease -n flux-system falco

# Force reconcile (GitOps approach)
flux reconcile kustomization falco --with-source

# View Falco logs (security events)
kubectl logs -n falco-system -l app.kubernetes.io/name=falco --tail=50

# View Falcosidekick logs (alert forwarding)
kubectl logs -n falco-system -l app.kubernetes.io/name=falcosidekick --tail=20
```

## Troubleshooting

### Common Issues

1. **Driver fails to load**
   - **Symptom**: Falco pods crash with eBPF errors
   - **Resolution**: Verify Talos has `lockdown=integrity` kernel arg (not `lockdown=confidentiality`)

2. **Alerts not appearing in VictoriaLogs**
   - **Symptom**: Falco detecting events but not visible in Grafana
   - **Resolution**: Check Falcosidekick connectivity to VictoriaLogs endpoint

## Future Enhancements

### Falco-talon (Automated Response)

Falco-talon can be enabled to automatically respond to threats:

- Kill malicious containers
- Add network policies
- Label suspicious pods

Currently disabled to focus on detection. Enable in values.yaml when ready:
`falco-talon.enabled: true`

Note: Automated responses are ephemeral and don't persist in Git.
Flux will recreate resources in clean state after response actions.

## References

- [Falco Documentation](https://falco.org/docs/)
- [Falco Helm Chart](https://github.com/falcosecurity/charts/tree/master/charts/falco)
- [Falcosidekick](https://github.com/falcosecurity/falcosidekick)
