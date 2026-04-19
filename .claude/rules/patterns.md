---
paths: [cluster/**]
---

# Cluster Patterns

## App Structure

```text
cluster/apps/<namespace>/
├── namespace.yaml          # Namespace with PSA labels
├── kustomization.yaml      # References namespace + app ks.yaml files
├── <app>/                  # Single app
│   ├── ks.yaml
│   ├── app/
│   │   ├── kustomization.yaml
│   │   ├── release.yaml        # HelmRelease
│   │   ├── values.yaml         # Helm values
│   │   ├── vpa.yaml            # VPA (recommendation-only)
│   │   └── *-secrets.sops.yaml # Encrypted secrets
│   └── <optional>/         # Optional dependent resources (e.g., ingress/)
├── <app1>/                 # Multiple apps (e.g., operator + instance)
│   ├── ks.yaml
│   └── app/
└── <app2>/
    ├── ks.yaml
    └── app/
```

## Multiple Kustomizations

When an app has optional resources that depend on it (e.g., ingress routes), add multiple Kustomizations in the same `ks.yaml`:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app myapp
spec:
  path: ./cluster/apps/<namespace>/<app>/app
  ...
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: myapp-ingress
spec:
  path: ./cluster/apps/<namespace>/<app>/ingress
  dependsOn:
    - name: myapp
    - name: other-dependency
  ...
```

## Variable Substitution

Flux `postBuild.substituteFrom` injects variables into all Kustomizations via patches in `cluster/flux/cluster/ks.yaml`. Two sources:

### Source: `cluster-settings` ConfigMap (`cluster/flux/meta/cluster-settings.yaml`)

| Variable | Description |
|----------|-------------|
| `TIMEZONE` | Cluster timezone |
| `CLUSTER_ISSUER` | Active cert-manager ClusterIssuer |

### Source: `cluster-secrets` Secret (`cluster/flux/meta/cluster-secrets.sops.yaml`)

| Variable | Description |
|----------|-------------|
| `CLUSTER_NAME` | Cluster name |
| `CLUSTER_DOMAIN` | Internal cluster domain |
| `EXTERNAL_DOMAIN` | Public-facing domain |
| `KUBEAPI_VIP` | Kubernetes API VIP |
| `ACME_EMAIL` | ACME certificate email |
| `ZEROSSL_EAB_KID` | ZeroSSL EAB key ID |
| `MY_AUTHENTIK_USER_EMAIL` | Admin user email |
| `E2_1_IP4`, `E2_2_IP4`, `E2_3_IP4` | Control plane node IPs |
| `MS_01_1_IP4`, `MS_01_2_IP4`, `MS_01_3_IP4` | Worker node IPs |
| `GATEWAY_IP4` | Network gateway |
| `CLUSTER_NODE_CIDR_IP4` | Node CIDR |
| `CLUSTER_POD_CIDR_IP4` | Pod CIDR |
| `CLUSTER_SVC_CIDR_IP4` | Service CIDR |
| `CLUSTER_LB_CIDR_START_IP4`, `CLUSTER_LB_CIDR_STOP_IP4` | LoadBalancer IP range |
| `LAN_CIDR_IP4`, `VPN_CIDR_IP4`, `TELEPORT_CIDR_IP4`, `DEVCONTAINER_CIDR_IP4` | Network CIDRs |
| `KUBELET_CSR_APPROVER_REGEX` | CSR approver pattern |
| `DNS_SERVER_DOMAIN`, `DNS_SERVER_SECONDARY_DOMAIN` | Technitium DNS domains |
| `TRAEFIK_IP4` | Traefik LoadBalancer IP |
| `TECHNITIUM_IP4`, `TECHNITIUM_SECONDARY_IP4` | DNS server IPs |
| `NTP_IP4` | NTP server IP |
| `NUT_IP4` | UPS NUT server IP |
| `MOSQUITTO_IP4` | MQTT broker IP |
| `HOME_ASSISTANT_IP4` | Home Assistant IP |
| `BEDROCK_CONNECT_IP4` | Bedrock Connect IP |
| `CRAFTY_CONTROLLER_IP4` | Crafty Controller IP |
| `MINECRAFT_BEDROCK_1_IP4`, `MINECRAFT_BEDROCK_2_IP4`, `MINECRAFT_BEDROCK_3_IP4` | Minecraft server IPs |

### Opt-out

To disable substitution on a Kustomization, add label: `substitution.flux.home.arpa/disabled: "true"`

## SOPS Naming

Pattern: `<name>-secrets.sops.yaml` or `<name>.sops.yaml`

## Helm Values

Before modifying Helm values, ALWAYS check upstream/source values.yaml first:

- Use Context7 or WebFetch with raw.githubusercontent.com to find correct key paths
- Never assume key names
- Verify the chart version matches when checking upstream docs

## VPA (Vertical Pod Autoscaler)

Every workload must include a `vpa.yaml` in its `app/` directory.

- `updateMode: "Off"` — recommendation-only
- Per-container `containerPolicies` (no wildcards)
- `minAllowed` = `cpu: 1m, memory: 1Mi` (unclamped for accurate recommendations)
- `maxAllowed` = current resource limits (omit CPU if no CPU limit is set)
- Containers with no resource specs: omit from `containerPolicies`
- `targetRef.name` must match the actual resource name in the cluster
- No `dependsOn: vertical-pod-autoscaler` needed — CRDs are installed via Talos `extraManifests`
- Schema: `https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json`

If a recommendation hits a boundary, adjust `minAllowed`/`maxAllowed` and recheck.

## Descheduler Namespace Exclusion

To exclude a namespace from descheduler eviction:

1. Add the label to its `namespace.yaml`:

```yaml
metadata:
  labels:
    descheduler.kubernetes.io/exclude: "true"
```

2. Add the namespace to the per-plugin `namespaces.exclude` lists in `cluster/apps/kube-system/descheduler/app/values.yaml`.

> **Note:** Per-plugin exclusion lists are required due to an upstream bug in descheduler v0.35.1 where `namespaceLabelSelector` ignores `matchExpressions` when `matchLabels` is empty. The labels are maintained for future migration to `DefaultEvictor.namespaceLabelSelector` once the bug is fixed.
