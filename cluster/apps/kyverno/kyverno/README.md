# kyverno - Policy Engine

## Overview

Kyverno is a Kubernetes-native policy engine that validates, mutates, and generates resources. It runs as an admission controller, intercepting API requests to enforce policies without requiring a separate policy language.

In this homelab, Kyverno is deployed as critical-infrastructure with four controllers:

- **Admission Controller** - Validates/mutates resources during API requests
- **Background Controller** - Processes existing resources and generate rules
- **Cleanup Controller** - Handles resource cleanup policies
- **Reports Controller** - Generates policy reports

## Prerequisites

- Kubernetes cluster with Flux CD installed
- cert-manager (for webhook certificates)

## Operation

### Key Commands

```bash
# Check Kyverno pod status
kubectl get pods -n kyverno

# Check HelmRelease status
flux get helmrelease -n kyverno kyverno

# Force reconcile
flux reconcile kustomization kyverno --with-source

# View admission controller logs
kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller

# View background controller logs
kubectl logs -n kyverno -l app.kubernetes.io/component=background-controller

# List all policies
kubectl get clusterpolicy,policy -A

# Check policy status
kubectl get clusterpolicy <policy-name> -o jsonpath='{.status.conditions}'
```

### Policy Management

```bash
# View policy reports
kubectl get policyreport -A
kubectl get clusterpolicyreport

# Check admission events
kubectl get events -n kyverno --field-selector reason=PolicyViolation
```

## Troubleshooting

### Common Issues

1. **Policy validation webhook denies changes**

   - **Symptom**: `admission webhook "validate-policy.kyverno.svc" denied the request`
   - **Resolution**: For generate rule changes to immutable fields, delete the policy first:

     ```bash
     kubectl delete clusterpolicy <policy-name>
     flux reconcile ks kyverno-policies --with-source
     ```

2. **Webhook not ready**

   - **Symptom**: API requests timeout or fail with webhook errors
   - **Diagnosis**: Check admission controller pods and certificates
   - **Resolution**:

     ```bash
     kubectl get pods -n kyverno -l app.kubernetes.io/component=admission-controller
     kubectl get validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg
     ```

3. **Generate rules not creating resources**

   - **Symptom**: Expected generated resources missing
   - **Diagnosis**: Check background controller logs
   - **Resolution**:

     ```bash
     kubectl logs -n kyverno -l app.kubernetes.io/component=background-controller --tail=50
     kubectl get updaterequest -A  # Check pending updates
     ```

4. **High memory usage**

   - **Symptom**: Controllers OOMKilled
   - **Diagnosis**: Check policy report volume and cleanup settings
   - **Resolution**: Adjust memory limits in values.yaml or reduce report retention

## References

- [Kyverno Documentation](https://kyverno.io/docs/)
- [Kyverno Policies](https://kyverno.io/policies/)
- [Kyverno Helm Chart](https://github.com/kyverno/kyverno/tree/main/charts/kyverno)
