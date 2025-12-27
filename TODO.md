# Project TODOs

## Infrastructure

### NUT / UPS Shutdown
- [ ] Enable shutdown-orchestrator (uncomment in `cluster/apps/nut-system/kustomization.yaml`)
- [ ] Test dry-run mode with brief power disconnect (<30s)
- [ ] Validate full shutdown sequence in dry-run (>30s disconnect)
- [ ] Switch to live mode (`DRY_RUN=false`) after validation
- [ ] Test recovery job after simulated outage

### Thermal / Hardware
- [ ] Investigate ms-01-2 thermal throttling (2025-12-26 22:35 AEDT, load avg 2.3)
  - CPU: Intel i5-12600H (4 P-cores hyperthreaded + 8 E-cores)
  - Throttle counts since boot:
    - P-core 4 (CPUs 2-3): 576 throttles
    - P-core 12 (CPUs 6-7): 216 throttles
    - P-core 0 (CPUs 0-1): 9 throttles
  - Root cause: rook-ceph-operator peaked at 2458m during throttle window
  - Consider: CPU limits on observability stack, or spread Ceph operator

## Knowledge Base / Research

### Helm Stuck Releases
- [ ] Document how to force-fail a stuck HelmRelease to apply pending fix
  - Workaround: `helm rollback <release> -n <ns> 0` + delete/recreate Kustomization

### YAML Schemas
- [ ] Research generating and hosting private YAML schemas

## Testing / CI

### Pre-deployment Testing
- [ ] Research testing strategies for GitOps/Flux workflows (preview environments, PR validation)
- [ ] Evaluate options: Flux diff/dry-run, ephemeral clusters, policy validation (Kyverno/OPA)
- [ ] Implement PR validation pipeline for manifests (schema validation, policy checks)
- [ ] Set up pre-deployment testing mechanism (staging namespace or ephemeral cluster)
