# GitHub App Token Rotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace static GitHub PATs with auto-rotating OAuth tokens via GitHub Apps, deploy a GitHub MCP server, and split claude-agents into write/read namespaces.

**Architecture:** CronJob in `github-system` refreshes OAuth tokens for two GitHub Apps (write + read), writes to a source Secret. ESO syncs tokens cross-namespace. Kyverno injects credentials into dynamically spawned Claude runner pods. GitHub MCP server deployed as a separate service.

**Tech Stack:** Kubernetes CronJob, External Secrets Operator, Kyverno, Cilium CNPs, Flux/Kustomize, app-template Helm chart

**Spec:** `docs/superpowers/specs/2026-03-31-github-app-token-rotation-design.md`
**Issue:** #829

---

## File Map

### New Files

| File | Responsibility |
| ---- | ------------- |
| `cluster/apps/github-system/namespace.yaml` | Namespace with PSA labels |
| `cluster/apps/github-system/kustomization.yaml` | Root kustomization referencing ks.yaml |
| `cluster/apps/github-system/github-token-rotation/ks.yaml` | Flux Kustomization targeting github-system |
| `cluster/apps/github-system/github-token-rotation/app/kustomization.yaml` | App kustomization listing all resources |
| `cluster/apps/github-system/github-token-rotation/app/service-account.yaml` | CronJob SA |
| `cluster/apps/github-system/github-token-rotation/app/cronjob.yaml` | Token rotation CronJob |
| `cluster/apps/github-system/github-token-rotation/app/role.yaml` | CronJob RBAC in github-system (secret read/patch) |
| `cluster/apps/github-system/github-token-rotation/app/role-binding.yaml` | CronJob RoleBinding in github-system |
| `cluster/apps/github-system/github-token-rotation/app/network-policies.yaml` | CNP: egress to github.com + kube-apiserver |
| `cluster/apps/github-system/github-token-rotation/app/reader-role.yaml` | ESO reader Role (shared, in github-system) |
| `cluster/apps/github-system/github-token-rotation/app/reader-role-binding-claude-agents-write.yaml` | RoleBinding for claude-agents-write reader SA |
| `cluster/apps/github-system/github-token-rotation/app/reader-role-binding-claude-agents-read.yaml` | RoleBinding for claude-agents-read reader SA |
| `cluster/apps/github-system/github-token-rotation/app/reader-role-binding-openclaw.yaml` | RoleBinding for openclaw reader SA |
| `cluster/apps/github-system/github-token-rotation/app/reader-role-binding-github-mcp.yaml` | RoleBinding for github-mcp reader SA |
| `cluster/apps/claude-agents-write/namespace.yaml` | Namespace with PSA + descheduler labels |
| `cluster/apps/claude-agents-write/kustomization.yaml` | Root kustomization |
| `cluster/apps/claude-agents-write/claude-agents/ks.yaml` | Flux Kustomization |
| `cluster/apps/claude-agents-write/claude-agents/app/kustomization.yaml` | App kustomization |
| `cluster/apps/claude-agents-write/claude-agents/app/rbac.yaml` | Agent pod SA |
| `cluster/apps/claude-agents-write/claude-agents/app/rbac-spawner.yaml` | n8n cross-ns pod creation |
| `cluster/apps/claude-agents-write/claude-agents/app/network-policies.yaml` | CNPs (migrated from claude-agents) |
| `cluster/apps/claude-agents-write/claude-agents/app/github-secret-store.yaml` | ESO SecretStore + reader SA |
| `cluster/apps/claude-agents-write/claude-agents/app/github-external-secret.yaml` | ESO ExternalSecret (write-hosts.yml) |
| `cluster/apps/claude-agents-write/claude-agents/app/github-ssh-external-secret.yaml` | ESO ExternalSecret (SSH key) |
| `cluster/apps/claude-agents-write/claude-agents/app/github-bot-gitconfig.yaml` | ConfigMap for git config |
| `cluster/apps/claude-agents-write/claude-agents/app/github-rotation-rbac.yaml` | CronJob force-sync RBAC |
| `cluster/apps/claude-agents-read/namespace.yaml` | Namespace with PSA + descheduler labels |
| `cluster/apps/claude-agents-read/kustomization.yaml` | Root kustomization |
| `cluster/apps/claude-agents-read/claude-agents/ks.yaml` | Flux Kustomization |
| `cluster/apps/claude-agents-read/claude-agents/app/kustomization.yaml` | App kustomization |
| `cluster/apps/claude-agents-read/claude-agents/app/rbac.yaml` | Agent pod SA |
| `cluster/apps/claude-agents-read/claude-agents/app/rbac-spawner.yaml` | n8n cross-ns pod creation |
| `cluster/apps/claude-agents-read/claude-agents/app/network-policies.yaml` | CNPs (same as write) |
| `cluster/apps/claude-agents-read/claude-agents/app/github-secret-store.yaml` | ESO SecretStore + reader SA |
| `cluster/apps/claude-agents-read/claude-agents/app/github-external-secret.yaml` | ESO ExternalSecret (read-hosts.yml) |
| `cluster/apps/claude-agents-read/claude-agents/app/github-ssh-external-secret.yaml` | ESO ExternalSecret (SSH key) |
| `cluster/apps/claude-agents-read/claude-agents/app/github-bot-gitconfig.yaml` | ConfigMap for git config |
| `cluster/apps/claude-agents-read/claude-agents/app/github-rotation-rbac.yaml` | CronJob force-sync RBAC |
| `cluster/apps/github-mcp/namespace.yaml` | Namespace with PSA labels |
| `cluster/apps/github-mcp/kustomization.yaml` | Root kustomization |
| `cluster/apps/github-mcp/github-mcp-server/ks.yaml` | Flux Kustomization |
| `cluster/apps/github-mcp/github-mcp-server/app/kustomization.yaml` | App kustomization with configMapGenerator |
| `cluster/apps/github-mcp/github-mcp-server/app/kustomizeconfig.yaml` | Name reference transformer |
| `cluster/apps/github-mcp/github-mcp-server/app/release.yaml` | HelmRelease (app-template) |
| `cluster/apps/github-mcp/github-mcp-server/app/values.yaml` | Helm values |
| `cluster/apps/github-mcp/github-mcp-server/app/network-policies.yaml` | CNPs (egress github API, ingress from claude-agents) |
| `cluster/apps/github-mcp/github-mcp-server/app/github-secret-store.yaml` | ESO SecretStore + reader SA |
| `cluster/apps/github-mcp/github-mcp-server/app/github-external-secret.yaml` | ESO ExternalSecret (read-access-token) |
| `cluster/apps/github-mcp/github-mcp-server/app/vpa.yaml` | VPA for the MCP server |
| `cluster/apps/github-system/github-token-rotation/app/vmrule.yaml` | VMRule alerts for CronJob failures |
| `cluster/apps/openclaw/openclaw/app/github-secret-store.yaml` | ESO SecretStore + reader SA for openclaw |
| `cluster/apps/openclaw/openclaw/app/github-external-secret.yaml` | ESO ExternalSecret (write-access-token) |
| `cluster/apps/openclaw/openclaw/app/github-rotation-rbac.yaml` | CronJob force-sync RBAC for openclaw |
| `cluster/apps/kyverno/policies/app/inject-github-credentials.yaml` | ClusterPolicy for credential injection |

### Modified Files

| File | Change |
| ---- | ------ |
| `cluster/apps/kustomization.yaml` | Add `github-system`, `claude-agents-write`, `claude-agents-read`, `github-mcp`; remove `claude-agents` |
| `cluster/apps/n8n-system/n8n/ks.yaml` | Update `dependsOn` from `claude-agents` to `claude-agents-write` |
| `cluster/apps/kyverno/policies/app/kustomization.yaml` | Add `inject-github-credentials.yaml` |
| `cluster/apps/kube-system/descheduler/app/values.yaml` | Replace `claude-agents` with `claude-agents-write` + `claude-agents-read` |
| `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml` | Update CNP: `claude-agents` -> `claude-agents-write` + `claude-agents-read` |
| `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml` | Same CNP update |
| `cluster/apps/openclaw/openclaw/app/kustomization.yaml` | Add ESO and rotation RBAC resources |
| `cluster/apps/openclaw/openclaw/app/values.yaml` | Override GIT_CODE_TOKEN with ESO-managed secret |
| `cluster/apps/github-system/github-token-rotation/app/kustomization.yaml` | Progressive additions across Tasks 1-4, 13 |

### Deleted (after migration verified)

| File | Why |
| ---- | --- |
| `cluster/apps/claude-agents/` (entire directory) | Replaced by `claude-agents-write` and `claude-agents-read` |

---

## Task 1: github-system Namespace + Flux Scaffolding

**Files:**
- Create: `cluster/apps/github-system/namespace.yaml`
- Create: `cluster/apps/github-system/kustomization.yaml`
- Create: `cluster/apps/github-system/github-token-rotation/ks.yaml`
- Create: `cluster/apps/github-system/github-token-rotation/app/kustomization.yaml`

- [ ] **Step 1: Create namespace.yaml**

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: github-system
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

- [ ] **Step 2: Create kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./github-token-rotation/ks.yaml
```

- [ ] **Step 3: Create ks.yaml**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas-cjso.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app github-token-rotation
  namespace: flux-system
spec:
  targetNamespace: github-system
  path: ./cluster/apps/github-system/github-token-rotation/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  prune: true
  timeout: 5m
  wait: true
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

- [ ] **Step 4: Create app/kustomization.yaml**

Start with just the SOPS secrets (already created by user). We'll add more resources in later tasks.

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./github-app-credentials.sops.yaml
  - ./github-bot-credentials.sops.yaml
  - ./github-bot-ssh-key.sops.yaml
```

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/github-system/namespace.yaml \
  cluster/apps/github-system/kustomization.yaml \
  cluster/apps/github-system/github-token-rotation/ks.yaml \
  cluster/apps/github-system/github-token-rotation/app/kustomization.yaml
git commit -m "feat(github-system): add namespace and Flux scaffolding

Ref #829"
```

---

## Task 2: CronJob ServiceAccount + RBAC + CNP

**Files:**
- Create: `cluster/apps/github-system/github-token-rotation/app/service-account.yaml`
- Create: `cluster/apps/github-system/github-token-rotation/app/role.yaml`
- Create: `cluster/apps/github-system/github-token-rotation/app/role-binding.yaml`
- Create: `cluster/apps/github-system/github-token-rotation/app/network-policies.yaml`
- Modify: `cluster/apps/github-system/github-token-rotation/app/kustomization.yaml`

- [ ] **Step 1: Create service-account.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/serviceaccount-v1.json
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-token-rotation
  namespace: github-system
```

- [ ] **Step 2: Create role.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/role-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: github-token-rotation
  namespace: github-system
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["github-bot-credentials"]
    verbs: ["get", "patch"]
```

- [ ] **Step 3: Create role-binding.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/rolebinding-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-token-rotation
  namespace: github-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: github-token-rotation
subjects:
  - kind: ServiceAccount
    name: github-token-rotation
    namespace: github-system
```

- [ ] **Step 4: Create network-policies.yaml**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to github.com for token refresh
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-github-egress
spec:
  endpointSelector:
    matchLabels:
      app: github-token-rotation
  egress:
    - toFQDNs:
        - matchName: github.com
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to kube-apiserver for kubectl patch operations
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-kube-api-egress
spec:
  endpointSelector:
    matchLabels:
      app: github-token-rotation
  egress:
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
```

- [ ] **Step 5: Update app/kustomization.yaml**

Add the new resources:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./github-app-credentials.sops.yaml
  - ./github-bot-credentials.sops.yaml
  - ./github-bot-ssh-key.sops.yaml
  - ./service-account.yaml
  - ./role.yaml
  - ./role-binding.yaml
  - ./network-policies.yaml
```

- [ ] **Step 6: Commit**

```bash
git add cluster/apps/github-system/github-token-rotation/app/service-account.yaml \
  cluster/apps/github-system/github-token-rotation/app/role.yaml \
  cluster/apps/github-system/github-token-rotation/app/role-binding.yaml \
  cluster/apps/github-system/github-token-rotation/app/network-policies.yaml \
  cluster/apps/github-system/github-token-rotation/app/kustomization.yaml
git commit -m "feat(github-system): add CronJob RBAC and network policies

Ref #829"
```

---

## Task 3: Token Rotation CronJob

**Files:**
- Create: `cluster/apps/github-system/github-token-rotation/app/cronjob.yaml`
- Modify: `cluster/apps/github-system/github-token-rotation/app/kustomization.yaml`

**Reference:** `cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/cronjob.yaml`

- [ ] **Step 1: Create cronjob.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/cronjob-batch-v1.json
apiVersion: batch/v1
kind: CronJob
metadata:
  name: github-token-rotation
  namespace: github-system
spec:
  schedule: "0 */4 * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        metadata:
          labels:
            app: github-token-rotation
        spec:
          securityContext:
            runAsNonRoot: true
            runAsUser: 10001
            runAsGroup: 10001
          serviceAccountName: github-token-rotation
          containers:
            - name: rotate-tokens
              image: alpine/k8s:1.35.3@sha256:097aa60cbef561146757c7494468e9d7b04d843597ad1a1515ed09d0708c8014
              command:
                - /bin/sh
                - -c
                - |
                  set -e

                  MAX_RETRIES=3

                  # Refresh a GitHub App OAuth token and update the source secret
                  refresh_token() {
                    PREFIX="$$1"          # "write" or "read"
                    CLIENT_ID="$$2"
                    CLIENT_SECRET="$$3"

                    echo "=== Refreshing $${PREFIX} App token ==="

                    # Read current refresh token from source secret
                    CURRENT_REFRESH=$$(kubectl get secret github-bot-credentials \
                      -n github-system \
                      -o jsonpath="{.data.$${PREFIX}-refresh-token}" | base64 -d)

                    if [ -z "$${CURRENT_REFRESH}" ]; then
                      echo "ERROR: No refresh token found for $${PREFIX}"
                      return 1
                    fi

                    # Call GitHub OAuth token refresh endpoint
                    RESPONSE=$$(curl -sf -X POST https://github.com/login/oauth/access_token \
                      -d "client_id=$${CLIENT_ID}" \
                      -d "client_secret=$${CLIENT_SECRET}" \
                      -d "grant_type=refresh_token" \
                      -d "refresh_token=$${CURRENT_REFRESH}" \
                      -H "Accept: application/json")

                    # Parse response
                    NEW_ACCESS=$$(echo "$${RESPONSE}" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
                    NEW_REFRESH=$$(echo "$${RESPONSE}" | grep -o '"refresh_token":"[^"]*"' | cut -d'"' -f4)

                    if [ -z "$${NEW_ACCESS}" ] || [ -z "$${NEW_REFRESH}" ]; then
                      echo "ERROR: Failed to parse tokens from response"
                      echo "Response: $${RESPONSE}" | grep -o '"error[^}]*' || true
                      return 1
                    fi

                    echo "Tokens received, updating source secret..."

                    # Build hosts.yml content
                    HOSTS_YML=$$(printf 'github.com:\n  oauth_token: %s\n  user: spruyt-labs-bot\n' "$${NEW_ACCESS}")

                    # Atomic patch - all keys in one operation
                    ATTEMPT=0
                    while [ $$ATTEMPT -lt $$MAX_RETRIES ]; do
                      ATTEMPT=$$((ATTEMPT + 1))
                      echo "Write attempt $${ATTEMPT}/$${MAX_RETRIES}..."

                      kubectl patch secret github-bot-credentials -n github-system --type='json' -p="[
                        {\"op\": \"replace\", \"path\": \"/data/$${PREFIX}-access-token\", \"value\": \"$$(echo -n $${NEW_ACCESS} | base64 -w0)\"},
                        {\"op\": \"replace\", \"path\": \"/data/$${PREFIX}-refresh-token\", \"value\": \"$$(echo -n $${NEW_REFRESH} | base64 -w0)\"},
                        {\"op\": \"replace\", \"path\": \"/data/$${PREFIX}-hosts.yml\", \"value\": \"$$(echo -n "$${HOSTS_YML}" | base64 -w0)\"}
                      ]"

                      # Read-after-write verification
                      VERIFIED=$$(kubectl get secret github-bot-credentials \
                        -n github-system \
                        -o jsonpath="{.data.$${PREFIX}-access-token}" | base64 -d)

                      if [ "$${VERIFIED}" = "$${NEW_ACCESS}" ]; then
                        echo "Write verified for $${PREFIX}"
                        break
                      fi

                      echo "WARNING: Write verification failed, retrying..."
                      if [ $$ATTEMPT -eq $$MAX_RETRIES ]; then
                        echo "ERROR: Write verification failed after $${MAX_RETRIES} attempts"
                        return 1
                      fi
                      sleep 2
                    done

                    echo "=== $${PREFIX} App token refreshed ==="
                  }

                  # Force-sync ExternalSecrets in consumer namespaces
                  force_sync_consumers() {
                    echo "=== Force-syncing ExternalSecrets in consumer namespaces ==="

                    for NS in claude-agents-write claude-agents-read openclaw github-mcp; do
                      for ES_NAME in github-bot-credentials github-bot-ssh-key; do
                        # Check if ExternalSecret exists before patching
                        if kubectl get externalsecret "$${ES_NAME}" -n "$${NS}" >/dev/null 2>&1; then
                          echo "Force-syncing $${ES_NAME} in $${NS}..."
                          kubectl patch externalsecret "$${ES_NAME}" -n "$${NS}" \
                            --type='merge' \
                            -p="{\"metadata\":{\"annotations\":{\"force-sync\":\"$$(date +%s)\"}}}"
                        fi
                      done
                    done

                    echo "=== Force-sync complete ==="
                  }

                  # Main
                  refresh_token "write" "$${WRITE_CLIENT_ID}" "$${WRITE_CLIENT_SECRET}"
                  refresh_token "read" "$${READ_CLIENT_ID}" "$${READ_CLIENT_SECRET}"
                  force_sync_consumers

                  echo "All token rotations completed successfully!"
              env:
                - name: WRITE_CLIENT_ID
                  valueFrom:
                    secretKeyRef:
                      name: github-app-credentials
                      key: write-client-id
                - name: WRITE_CLIENT_SECRET
                  valueFrom:
                    secretKeyRef:
                      name: github-app-credentials
                      key: write-client-secret
                - name: READ_CLIENT_ID
                  valueFrom:
                    secretKeyRef:
                      name: github-app-credentials
                      key: read-client-id
                - name: READ_CLIENT_SECRET
                  valueFrom:
                    secretKeyRef:
                      name: github-app-credentials
                      key: read-client-secret
              resources:
                requests:
                  cpu: 10m
                  memory: 32Mi
                limits:
                  cpu: 100m
                  memory: 128Mi
              securityContext:
                allowPrivilegeEscalation: false
                capabilities:
                  drop:
                    - ALL
                readOnlyRootFilesystem: true
                runAsNonRoot: true
                runAsUser: 10001
                runAsGroup: 10001
                seccompProfile:
                  type: RuntimeDefault
          restartPolicy: OnFailure
```

- [ ] **Step 2: Update app/kustomization.yaml**

Add `cronjob.yaml` to resources list:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./github-app-credentials.sops.yaml
  - ./github-bot-credentials.sops.yaml
  - ./github-bot-ssh-key.sops.yaml
  - ./service-account.yaml
  - ./role.yaml
  - ./role-binding.yaml
  - ./network-policies.yaml
  - ./cronjob.yaml
```

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/github-system/github-token-rotation/app/cronjob.yaml \
  cluster/apps/github-system/github-token-rotation/app/kustomization.yaml
git commit -m "feat(github-system): add token rotation CronJob

Refreshes write and read App OAuth tokens every 4h, writes
to source secret, force-syncs ExternalSecrets in consumers.

Ref #829"
```

---

## Task 4: ESO Reader RBAC (in github-system)

**Files:**
- Create: `cluster/apps/github-system/github-token-rotation/app/reader-role.yaml`
- Create: `cluster/apps/github-system/github-token-rotation/app/reader-role-binding-claude-agents-write.yaml`
- Create: `cluster/apps/github-system/github-token-rotation/app/reader-role-binding-claude-agents-read.yaml`
- Create: `cluster/apps/github-system/github-token-rotation/app/reader-role-binding-openclaw.yaml`
- Create: `cluster/apps/github-system/github-token-rotation/app/reader-role-binding-github-mcp.yaml`
- Modify: `cluster/apps/github-system/github-token-rotation/app/kustomization.yaml`

**Reference:** `cluster/apps/authentik-system/authentik/app/external-secrets-rbac.yaml`

- [ ] **Step 1: Create reader-role.yaml**

Single Role shared by all consumer reader SAs:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/role-rbac-v1.json
# Allows consumer namespace SAs to read github-bot-credentials and github-bot-ssh-key
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: github-token-reader
  namespace: github-system
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["github-bot-credentials", "github-bot-ssh-key"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["authorization.k8s.io"]
    resources: ["selfsubjectrulesreviews"]
    verbs: ["create"]
```

- [ ] **Step 2: Create reader-role-binding-claude-agents-write.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/rolebinding-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-token-reader-claude-agents-write
  namespace: github-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: github-token-reader
subjects:
  - kind: ServiceAccount
    name: github-secret-reader
    namespace: claude-agents-write
```

- [ ] **Step 3: Create reader-role-binding-claude-agents-read.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/rolebinding-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-token-reader-claude-agents-read
  namespace: github-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: github-token-reader
subjects:
  - kind: ServiceAccount
    name: github-secret-reader
    namespace: claude-agents-read
```

- [ ] **Step 4: Create reader-role-binding-openclaw.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/rolebinding-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-token-reader-openclaw
  namespace: github-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: github-token-reader
subjects:
  - kind: ServiceAccount
    name: github-secret-reader
    namespace: openclaw
```

- [ ] **Step 5: Create reader-role-binding-github-mcp.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/rolebinding-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-token-reader-github-mcp
  namespace: github-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: github-token-reader
subjects:
  - kind: ServiceAccount
    name: github-secret-reader
    namespace: github-mcp
```

- [ ] **Step 6: Update app/kustomization.yaml**

Add all reader RBAC resources:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./github-app-credentials.sops.yaml
  - ./github-bot-credentials.sops.yaml
  - ./github-bot-ssh-key.sops.yaml
  - ./service-account.yaml
  - ./role.yaml
  - ./role-binding.yaml
  - ./network-policies.yaml
  - ./cronjob.yaml
  - ./reader-role.yaml
  - ./reader-role-binding-claude-agents-write.yaml
  - ./reader-role-binding-claude-agents-read.yaml
  - ./reader-role-binding-openclaw.yaml
  - ./reader-role-binding-github-mcp.yaml
```

- [ ] **Step 7: Commit**

```bash
git add cluster/apps/github-system/github-token-rotation/app/reader-role.yaml \
  cluster/apps/github-system/github-token-rotation/app/reader-role-binding-claude-agents-write.yaml \
  cluster/apps/github-system/github-token-rotation/app/reader-role-binding-claude-agents-read.yaml \
  cluster/apps/github-system/github-token-rotation/app/reader-role-binding-openclaw.yaml \
  cluster/apps/github-system/github-token-rotation/app/reader-role-binding-github-mcp.yaml \
  cluster/apps/github-system/github-token-rotation/app/kustomization.yaml
git commit -m "feat(github-system): add ESO reader RBAC for consumer namespaces

Ref #829"
```

---

## Task 5: CronJob Force-Sync RBAC (in consumer namespaces)

The CronJob needs to patch ExternalSecrets in consumer namespaces to force-sync. This RBAC lives in each consumer namespace (same pattern as `cluster/apps/observability/victoria-metrics-k8s-stack/app/oauth-rotation-rbac.yaml`).

These files will be created inside each consumer namespace's app directory in later tasks. For now, we create the ones for namespaces that already exist: `openclaw`.

**Files:**
- Create: `cluster/apps/openclaw/openclaw/app/github-rotation-rbac.yaml`
- Modify: `cluster/apps/openclaw/openclaw/app/kustomization.yaml`

- [ ] **Step 1: Create github-rotation-rbac.yaml in openclaw**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/role-rbac-v1.json
# Role in openclaw namespace to allow CronJob to force-sync ExternalSecrets
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: github-token-rotation
  namespace: openclaw
rules:
  - apiGroups: ["external-secrets.io"]
    resources: ["externalsecrets"]
    resourceNames: ["github-bot-credentials"]
    verbs: ["get", "patch"]
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/rolebinding-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-token-rotation
  namespace: openclaw
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: github-token-rotation
subjects:
  - kind: ServiceAccount
    name: github-token-rotation
    namespace: github-system
```

- [ ] **Step 2: Update openclaw app/kustomization.yaml**

Read the current file and add `github-rotation-rbac.yaml` to the resources list.

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/github-rotation-rbac.yaml \
  cluster/apps/openclaw/openclaw/app/kustomization.yaml
git commit -m "feat(openclaw): add RBAC for github token rotation force-sync

Ref #829"
```

---

## Task 6: claude-agents-write Namespace

**Files:**
- Create: `cluster/apps/claude-agents-write/namespace.yaml`
- Create: `cluster/apps/claude-agents-write/kustomization.yaml`
- Create: `cluster/apps/claude-agents-write/claude-agents/ks.yaml`
- Create: `cluster/apps/claude-agents-write/claude-agents/app/kustomization.yaml`
- Create: `cluster/apps/claude-agents-write/claude-agents/app/rbac.yaml`
- Create: `cluster/apps/claude-agents-write/claude-agents/app/rbac-spawner.yaml`
- Create: `cluster/apps/claude-agents-write/claude-agents/app/network-policies.yaml`
- Create: `cluster/apps/claude-agents-write/claude-agents/app/github-secret-store.yaml`
- Create: `cluster/apps/claude-agents-write/claude-agents/app/github-external-secret.yaml`
- Create: `cluster/apps/claude-agents-write/claude-agents/app/github-ssh-external-secret.yaml`
- Create: `cluster/apps/claude-agents-write/claude-agents/app/github-bot-gitconfig.yaml`
- Create: `cluster/apps/claude-agents-write/claude-agents/app/github-rotation-rbac.yaml`

- [ ] **Step 1: Create namespace.yaml**

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: claude-agents-write
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    descheduler.kubernetes.io/exclude: "true"
```

- [ ] **Step 2: Create kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./claude-agents/ks.yaml
```

- [ ] **Step 3: Create ks.yaml**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas-cjso.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app claude-agents-write
  namespace: flux-system
spec:
  targetNamespace: claude-agents-write
  path: ./cluster/apps/claude-agents-write/claude-agents/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: github-token-rotation
  prune: true
  timeout: 5m
  wait: true
```

- [ ] **Step 4: Create app/rbac.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/serviceaccount-v1.json
# SA assigned to ephemeral Claude agent pods by the community node
apiVersion: v1
kind: ServiceAccount
metadata:
  name: claude-agent
```

- [ ] **Step 5: Create app/rbac-spawner.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/role-rbac-v1.json
# Role for n8n to manage ephemeral Claude agent pods
# n8n uses in-cluster SA auth -- bound to the n8n SA in n8n-system
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: claude-pod-manager
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["create", "get", "list", "watch", "delete"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["pods/status"]
    verbs: ["get"]
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/rolebinding-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: n8n-claude-spawner-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: claude-pod-manager
subjects:
  - kind: ServiceAccount
    name: n8n
    namespace: n8n-system
```

- [ ] **Step 6: Create app/network-policies.yaml**

Migrated from `cluster/apps/claude-agents/claude-agents/app/network-policies.yaml` with namespace references updated:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to kube-apiserver
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-kube-api-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow all egress to world -- agents need external APIs, npm, git, etc.
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-world-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEntities:
        - world
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to kubectl MCP server
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-kubectl-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kubectl-mcp
            k8s:app.kubernetes.io/name: kubectl-mcp-server
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to VictoriaMetrics MCP server
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-victoriametrics-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            k8s:app.kubernetes.io/name: mcp-victoriametrics
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to GitHub MCP server
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-github-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: github-mcp
            k8s:app.kubernetes.io/name: github-mcp-server
      toPorts:
        - ports:
            - port: "8082"
              protocol: TCP
```

- [ ] **Step 7: Create app/github-secret-store.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/serviceaccount-v1.json
# ServiceAccount for ESO to read secrets from github-system
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-secret-reader
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/external-secrets.io/secretstore_v1.json
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: github-secret-store
spec:
  provider:
    kubernetes:
      remoteNamespace: github-system
      server:
        url: "https://kubernetes.default.svc"
        caProvider:
          type: ConfigMap
          name: kube-root-ca.crt
          key: ca.crt
      auth:
        serviceAccount:
          name: github-secret-reader
```

- [ ] **Step 8: Create app/github-external-secret.yaml**

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/external-secrets.io/externalsecret_v1.json
# Syncs write-tier GitHub OAuth credentials from github-system
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: github-bot-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: SecretStore
    name: github-secret-store
  target:
    name: github-bot-credentials
    creationPolicy: Owner
  data:
    - secretKey: hosts.yml
      remoteRef:
        key: github-bot-credentials
        property: write-hosts.yml
```

- [ ] **Step 9: Create app/github-ssh-external-secret.yaml**

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/external-secrets.io/externalsecret_v1.json
# Syncs bot SSH key from github-system for git transport + commit signing
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: github-bot-ssh-key
spec:
  refreshInterval: 24h
  secretStoreRef:
    kind: SecretStore
    name: github-secret-store
  target:
    name: github-bot-ssh-key
    creationPolicy: Owner
  data:
    - secretKey: id_ed25519
      remoteRef:
        key: github-bot-ssh-key
        property: id_ed25519
    - secretKey: id_ed25519.pub
      remoteRef:
        key: github-bot-ssh-key
        property: id_ed25519.pub
```

- [ ] **Step 10: Create app/github-bot-gitconfig.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/configmap-v1.json
apiVersion: v1
kind: ConfigMap
metadata:
  name: github-bot-gitconfig
data:
  gitconfig: |
    [user]
        name = spruyt-labs-bot
        email = spruyt-labs-bot@users.noreply.github.com
    [gpg]
        format = ssh
    [commit]
        gpgsign = true
    [user]
        signingkey = /etc/git-ssh/id_ed25519
    [core]
        sshCommand = ssh -i /etc/git-ssh/id_ed25519 -o StrictHostKeyChecking=accept-new
```

- [ ] **Step 11: Create app/github-rotation-rbac.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/role-rbac-v1.json
# Role to allow CronJob to force-sync ExternalSecrets
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: github-token-rotation
rules:
  - apiGroups: ["external-secrets.io"]
    resources: ["externalsecrets"]
    resourceNames: ["github-bot-credentials", "github-bot-ssh-key"]
    verbs: ["get", "patch"]
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/rolebinding-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-token-rotation
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: github-token-rotation
subjects:
  - kind: ServiceAccount
    name: github-token-rotation
    namespace: github-system
```

- [ ] **Step 12: Create app/kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./rbac.yaml
  - ./rbac-spawner.yaml
  - ./network-policies.yaml
  - ./github-secret-store.yaml
  - ./github-external-secret.yaml
  - ./github-ssh-external-secret.yaml
  - ./github-bot-gitconfig.yaml
  - ./github-rotation-rbac.yaml
```

- [ ] **Step 13: Commit**

```bash
git add cluster/apps/claude-agents-write/namespace.yaml \
  cluster/apps/claude-agents-write/kustomization.yaml \
  cluster/apps/claude-agents-write/claude-agents/ks.yaml \
  cluster/apps/claude-agents-write/claude-agents/app/kustomization.yaml \
  cluster/apps/claude-agents-write/claude-agents/app/rbac.yaml \
  cluster/apps/claude-agents-write/claude-agents/app/rbac-spawner.yaml \
  cluster/apps/claude-agents-write/claude-agents/app/network-policies.yaml \
  cluster/apps/claude-agents-write/claude-agents/app/github-secret-store.yaml \
  cluster/apps/claude-agents-write/claude-agents/app/github-external-secret.yaml \
  cluster/apps/claude-agents-write/claude-agents/app/github-ssh-external-secret.yaml \
  cluster/apps/claude-agents-write/claude-agents/app/github-bot-gitconfig.yaml \
  cluster/apps/claude-agents-write/claude-agents/app/github-rotation-rbac.yaml
git commit -m "feat(claude-agents-write): add write-tier namespace with ESO and RBAC

Migrated from claude-agents with write-tier GitHub credentials
via ESO cross-namespace sync. Includes CNPs, spawner RBAC,
gitconfig ConfigMap, and rotation force-sync RBAC.

Ref #829"
```

---

## Task 7: claude-agents-read Namespace

Same structure as claude-agents-write but with read-tier credentials.

**Files:** Same set as Task 6, under `cluster/apps/claude-agents-read/`

- [ ] **Step 1: Create all files**

Copy the entire `claude-agents-write` structure to `claude-agents-read` with these changes:
- `namespace.yaml`: name `claude-agents-read`
- `ks.yaml`: name `claude-agents-read`, targetNamespace `claude-agents-read`
- `github-external-secret.yaml`: change `write-hosts.yml` to `read-hosts.yml`
- Everything else is identical (same SSH key, same gitconfig, same CNPs, same spawner RBAC)

**namespace.yaml:**
```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: claude-agents-read
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    descheduler.kubernetes.io/exclude: "true"
```

**ks.yaml:**
```yaml
---
# yaml-language-server: $schema=https://k8s-schemas-cjso.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app claude-agents-read
  namespace: flux-system
spec:
  targetNamespace: claude-agents-read
  path: ./cluster/apps/claude-agents-read/claude-agents/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: github-token-rotation
  prune: true
  timeout: 5m
  wait: true
```

**github-external-secret.yaml (the key difference):**
```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/external-secrets.io/externalsecret_v1.json
# Syncs read-tier GitHub OAuth credentials from github-system
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: github-bot-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: SecretStore
    name: github-secret-store
  target:
    name: github-bot-credentials
    creationPolicy: Owner
  data:
    - secretKey: hosts.yml
      remoteRef:
        key: github-bot-credentials
        property: read-hosts.yml
```

All other files (`kustomization.yaml`, `rbac.yaml`, `rbac-spawner.yaml`, `network-policies.yaml`, `github-secret-store.yaml`, `github-ssh-external-secret.yaml`, `github-bot-gitconfig.yaml`, `github-rotation-rbac.yaml`) are identical to Task 6.

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/claude-agents-read/namespace.yaml \
  cluster/apps/claude-agents-read/kustomization.yaml \
  cluster/apps/claude-agents-read/claude-agents/ks.yaml \
  cluster/apps/claude-agents-read/claude-agents/app/kustomization.yaml \
  cluster/apps/claude-agents-read/claude-agents/app/rbac.yaml \
  cluster/apps/claude-agents-read/claude-agents/app/rbac-spawner.yaml \
  cluster/apps/claude-agents-read/claude-agents/app/network-policies.yaml \
  cluster/apps/claude-agents-read/claude-agents/app/github-secret-store.yaml \
  cluster/apps/claude-agents-read/claude-agents/app/github-external-secret.yaml \
  cluster/apps/claude-agents-read/claude-agents/app/github-ssh-external-secret.yaml \
  cluster/apps/claude-agents-read/claude-agents/app/github-bot-gitconfig.yaml \
  cluster/apps/claude-agents-read/claude-agents/app/github-rotation-rbac.yaml
git commit -m "feat(claude-agents-read): add read-tier namespace with ESO and RBAC

Same structure as claude-agents-write but syncs read-hosts.yml
for read+comment OAuth scope.

Ref #829"
```

---

## Task 8: GitHub MCP Server

**Files:**
- Create: `cluster/apps/github-mcp/namespace.yaml`
- Create: `cluster/apps/github-mcp/kustomization.yaml`
- Create: `cluster/apps/github-mcp/github-mcp-server/ks.yaml`
- Create: `cluster/apps/github-mcp/github-mcp-server/app/kustomization.yaml`
- Create: `cluster/apps/github-mcp/github-mcp-server/app/kustomizeconfig.yaml`
- Create: `cluster/apps/github-mcp/github-mcp-server/app/release.yaml`
- Create: `cluster/apps/github-mcp/github-mcp-server/app/values.yaml`
- Create: `cluster/apps/github-mcp/github-mcp-server/app/network-policies.yaml`
- Create: `cluster/apps/github-mcp/github-mcp-server/app/github-secret-store.yaml`
- Create: `cluster/apps/github-mcp/github-mcp-server/app/github-external-secret.yaml`
- Create: `cluster/apps/github-mcp/github-mcp-server/app/github-rotation-rbac.yaml`
- Create: `cluster/apps/github-mcp/github-mcp-server/app/vpa.yaml`

**Reference:** `cluster/apps/kubectl-mcp/` for the full pattern

- [ ] **Step 1: Create namespace.yaml**

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: github-mcp
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

- [ ] **Step 2: Create root kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./github-mcp-server/ks.yaml
```

- [ ] **Step 3: Create ks.yaml**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas-cjso.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app github-mcp-server
  namespace: flux-system
spec:
  targetNamespace: github-mcp
  path: ./cluster/apps/github-mcp/github-mcp-server/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: github-token-rotation
  prune: true
  timeout: 5m
  wait: true
```

- [ ] **Step 4: Create app/kustomizeconfig.yaml**

```yaml
---
nameReference:
  - kind: ConfigMap
    version: v1
    fieldSpecs:
      - path: spec/valuesFrom/name
        kind: HelmRelease
```

- [ ] **Step 5: Create app/release.yaml**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: github-mcp-server
spec:
  chartRef:
    kind: OCIRepository
    name: app-template
    namespace: flux-system
  interval: 4h
  valuesFrom:
    - kind: ConfigMap
      name: github-mcp-server-values
```

- [ ] **Step 6: Create app/values.yaml**

```yaml
---
# Default values: https://github.com/bjw-s-labs/helm-charts/blob/main/charts/library/common/values.yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/refs/heads/main/charts/library/common/values.schema.json
defaultPodOptions:
  priorityClassName: low-priority
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    runAsGroup: 65534
    fsGroup: 65534
    seccompProfile:
      type: RuntimeDefault
controllers:
  github-mcp-server:
    strategy: Recreate
    containers:
      app:
        image:
          repository: ghcr.io/github/github-mcp-server
          tag: v0.32.0@sha256:2763823c63bcca718ce53850a1d7fcf2f501ec84028394f1b63ce7e9f4f9be28
          pullPolicy: IfNotPresent
        args:
          - "http"
          - "--port"
          - "8082"
        env:
          - name: GITHUB_PERSONAL_ACCESS_TOKEN
            valueFrom:
              secretKeyRef:
                name: github-mcp-credentials
                key: GITHUB_PERSONAL_ACCESS_TOKEN
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
        resources:
          requests:
            cpu: 10m
            memory: 64Mi
          limits:
            memory: 256Mi
        probes:
          liveness:
            enabled: true
            custom: true
            spec:
              tcpSocket:
                port: 8082
              initialDelaySeconds: 10
              periodSeconds: 30
              timeoutSeconds: 3
              failureThreshold: 3
          readiness:
            enabled: true
            custom: true
            spec:
              tcpSocket:
                port: 8082
              initialDelaySeconds: 5
              periodSeconds: 10
              timeoutSeconds: 3
              failureThreshold: 3
          startup:
            enabled: true
            custom: true
            spec:
              tcpSocket:
                port: 8082
              failureThreshold: 30
              periodSeconds: 5
service:
  app:
    controller: github-mcp-server
    ports:
      http:
        port: 8082
```

- [ ] **Step 7: Create app/network-policies.yaml**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to GitHub API
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-github-api-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: github-mcp-server
  egress:
    - toFQDNs:
        - matchName: api.github.com
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from Claude agent write pods
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-claude-agents-write-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: github-mcp-server
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: claude-agents-write
            k8s:managed-by: n8n-claude-code
      toPorts:
        - ports:
            - port: "8082"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from Claude agent read pods
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-claude-agents-read-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: github-mcp-server
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: claude-agents-read
            k8s:managed-by: n8n-claude-code
      toPorts:
        - ports:
            - port: "8082"
              protocol: TCP
```

- [ ] **Step 8: Create app/github-secret-store.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/serviceaccount-v1.json
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-secret-reader
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/external-secrets.io/secretstore_v1.json
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: github-secret-store
spec:
  provider:
    kubernetes:
      remoteNamespace: github-system
      server:
        url: "https://kubernetes.default.svc"
        caProvider:
          type: ConfigMap
          name: kube-root-ca.crt
          key: ca.crt
      auth:
        serviceAccount:
          name: github-secret-reader
```

- [ ] **Step 9: Create app/github-external-secret.yaml**

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/external-secrets.io/externalsecret_v1.json
# Syncs read-tier access token for GitHub MCP server
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: github-bot-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: SecretStore
    name: github-secret-store
  target:
    name: github-mcp-credentials
    creationPolicy: Owner
  data:
    - secretKey: GITHUB_PERSONAL_ACCESS_TOKEN
      remoteRef:
        key: github-bot-credentials
        property: read-access-token
```

- [ ] **Step 10: Create app/github-rotation-rbac.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/role-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: github-token-rotation
rules:
  - apiGroups: ["external-secrets.io"]
    resources: ["externalsecrets"]
    resourceNames: ["github-bot-credentials"]
    verbs: ["get", "patch"]
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/rolebinding-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-token-rotation
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: github-token-rotation
subjects:
  - kind: ServiceAccount
    name: github-token-rotation
    namespace: github-system
```

- [ ] **Step 11: Create app/vpa.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: github-mcp-server
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: github-mcp-server
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: app
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          memory: 256Mi
```

- [ ] **Step 12: Create app/kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./release.yaml
  - ./network-policies.yaml
  - ./github-secret-store.yaml
  - ./github-external-secret.yaml
  - ./github-rotation-rbac.yaml
  - ./vpa.yaml
configMapGenerator:
  - name: github-mcp-server-values
    namespace: github-mcp
    files:
      - values.yaml
configurations:
  - ./kustomizeconfig.yaml
```

- [ ] **Step 13: Commit**

```bash
git add cluster/apps/github-mcp/namespace.yaml \
  cluster/apps/github-mcp/kustomization.yaml \
  cluster/apps/github-mcp/github-mcp-server/ks.yaml \
  cluster/apps/github-mcp/github-mcp-server/app/kustomization.yaml \
  cluster/apps/github-mcp/github-mcp-server/app/kustomizeconfig.yaml \
  cluster/apps/github-mcp/github-mcp-server/app/release.yaml \
  cluster/apps/github-mcp/github-mcp-server/app/values.yaml \
  cluster/apps/github-mcp/github-mcp-server/app/network-policies.yaml \
  cluster/apps/github-mcp/github-mcp-server/app/github-secret-store.yaml \
  cluster/apps/github-mcp/github-mcp-server/app/github-external-secret.yaml \
  cluster/apps/github-mcp/github-mcp-server/app/github-rotation-rbac.yaml \
  cluster/apps/github-mcp/github-mcp-server/app/vpa.yaml
git commit -m "feat(github-mcp): deploy GitHub MCP server with ESO credentials

HTTP transport on port 8082, read-tier OAuth token via ESO.
CNPs allow egress to api.github.com, ingress from claude-agents.

Ref #829"
```

---

## Task 9: Kyverno ClusterPolicy

**Files:**
- Create: `cluster/apps/kyverno/policies/app/inject-github-credentials.yaml`
- Modify: `cluster/apps/kyverno/policies/app/kustomization.yaml`

- [ ] **Step 1: Create inject-github-credentials.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/kyverno.io/clusterpolicy_v1.json
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: inject-github-credentials
  annotations:
    policies.kyverno.io/title: Inject GitHub Credentials
    policies.kyverno.io/category: Credential Management
    policies.kyverno.io/severity: medium
    policies.kyverno.io/subject: Pod
    policies.kyverno.io/description: >-
      Injects GitHub bot credentials (gh CLI config, SSH key, gitconfig)
      into Claude agent pods spawned by n8n. Write and read namespaces
      get different OAuth scopes via ESO key mapping.
spec:
  background: false
  rules:
    - name: inject-write-creds
      match:
        any:
          - resources:
              kinds:
                - Pod
              namespaces:
                - claude-agents-write
              selector:
                matchLabels:
                  managed-by: n8n-claude-code
      mutate:
        patchStrategicMerge:
          spec:
            volumes:
              - name: github-gh-config
                secret:
                  secretName: github-bot-credentials
                  items:
                    - key: hosts.yml
                      path: hosts.yml
              - name: github-ssh-key
                secret:
                  secretName: github-bot-ssh-key
                  defaultMode: 0400
              - name: github-gitconfig
                configMap:
                  name: github-bot-gitconfig
            containers:
              - (name): "?*"
                env:
                  - name: GH_CONFIG_DIR
                    value: /etc/gh
                  - name: GIT_CONFIG_GLOBAL
                    value: /etc/gitconfig/gitconfig
                volumeMounts:
                  - name: github-gh-config
                    mountPath: /etc/gh
                    readOnly: true
                  - name: github-ssh-key
                    mountPath: /etc/git-ssh
                    readOnly: true
                  - name: github-gitconfig
                    mountPath: /etc/gitconfig
                    readOnly: true
    - name: inject-read-creds
      match:
        any:
          - resources:
              kinds:
                - Pod
              namespaces:
                - claude-agents-read
              selector:
                matchLabels:
                  managed-by: n8n-claude-code
      mutate:
        patchStrategicMerge:
          spec:
            volumes:
              - name: github-gh-config
                secret:
                  secretName: github-bot-credentials
                  items:
                    - key: hosts.yml
                      path: hosts.yml
              - name: github-ssh-key
                secret:
                  secretName: github-bot-ssh-key
                  defaultMode: 0400
              - name: github-gitconfig
                configMap:
                  name: github-bot-gitconfig
            containers:
              - (name): "?*"
                env:
                  - name: GH_CONFIG_DIR
                    value: /etc/gh
                  - name: GIT_CONFIG_GLOBAL
                    value: /etc/gitconfig/gitconfig
                volumeMounts:
                  - name: github-gh-config
                    mountPath: /etc/gh
                    readOnly: true
                  - name: github-ssh-key
                    mountPath: /etc/git-ssh
                    readOnly: true
                  - name: github-gitconfig
                    mountPath: /etc/gitconfig
                    readOnly: true
```

- [ ] **Step 2: Update kustomization.yaml**

Add the new policy to `cluster/apps/kyverno/policies/app/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./default-limitrange.yaml
  - ./helmrelease-defaults.yaml
  - ./inject-github-credentials.yaml
  - ./pss-restricted-defaults.yaml
  - ./topology-spread-policy.yaml
```

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/kyverno/policies/app/inject-github-credentials.yaml \
  cluster/apps/kyverno/policies/app/kustomization.yaml
git commit -m "feat(kyverno): add ClusterPolicy to inject GitHub credentials

Mutates Claude agent pods in write and read namespaces to mount
gh CLI config, SSH key, and gitconfig via Kyverno volumes.

Ref #829"
```

---

## Task 10: Update Existing Resources (Root Kustomization, n8n, CNPs, Descheduler)

**Files:**
- Modify: `cluster/apps/kustomization.yaml`
- Modify: `cluster/apps/n8n-system/n8n/ks.yaml`
- Modify: `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml`
- Modify: `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml`
- Modify: `cluster/apps/kube-system/descheduler/app/values.yaml`

- [ ] **Step 1: Update root kustomization**

In `cluster/apps/kustomization.yaml`, replace `./claude-agents` with the new namespace entries:

Old:
```yaml
  - ./claude-agents
  - ./vpa-system
```

New:
```yaml
  - ./github-system
  - ./claude-agents-write
  - ./claude-agents-read
  - ./github-mcp
  - ./vpa-system
```

- [ ] **Step 2: Update n8n dependsOn**

In `cluster/apps/n8n-system/n8n/ks.yaml`, replace the `claude-agents` dependency:

Old:
```yaml
  dependsOn:
    - name: authentik
    - name: cnpg-operator
    - name: plugin-barman-cloud
    - name: valkey
    - name: claude-agents
```

New:
```yaml
  dependsOn:
    - name: authentik
    - name: cnpg-operator
    - name: plugin-barman-cloud
    - name: valkey
    - name: claude-agents-write
```

- [ ] **Step 3: Update kubectl-mcp CNP**

Replace the `allow-claude-agents-ingress` policy (currently matches `claude-agents` namespace) with two rules for the new namespaces. In `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml`, replace the last CNP block:

Old:
```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from Claude agents (pod-to-pod MCP access)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-claude-agents-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: kubectl-mcp-server
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: claude-agents
            k8s:managed-by: n8n-claude-code
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
```

New:
```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from Claude agents (pod-to-pod MCP access)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-claude-agents-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: kubectl-mcp-server
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: claude-agents-write
            k8s:managed-by: n8n-claude-code
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: claude-agents-read
            k8s:managed-by: n8n-claude-code
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
```

- [ ] **Step 4: Update mcp-victoriametrics CNP**

Read the current file and apply the same pattern: replace `claude-agents` namespace with both `claude-agents-write` and `claude-agents-read`.

- [ ] **Step 5: Update descheduler values**

In `cluster/apps/kube-system/descheduler/app/values.yaml`, replace `claude-agents` with `claude-agents-write` and `claude-agents-read` in all per-plugin `namespaces.exclude` lists (5 occurrences based on grep).

- [ ] **Step 6: Commit**

```bash
git add cluster/apps/kustomization.yaml \
  cluster/apps/n8n-system/n8n/ks.yaml \
  cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml \
  cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml \
  cluster/apps/kube-system/descheduler/app/values.yaml
git commit -m "refactor(security): update CNPs and descheduler for split namespaces

Replace claude-agents references with claude-agents-write and
claude-agents-read in MCP server CNPs and descheduler exclusions.

Ref #829"
```

---

## Task 11: Remove Old claude-agents Namespace

Only after all new resources are deployed and verified.

**Files:**
- Delete: `cluster/apps/claude-agents/` (entire directory)

- [ ] **Step 1: Remove old claude-agents directory**

```bash
rm -rf cluster/apps/claude-agents/
```

- [ ] **Step 2: Commit**

```bash
git add -u cluster/apps/claude-agents/
git commit -m "refactor(claude-agents): remove old namespace, replaced by write/read split

Ref #829"
```

---

## Task 12: OpenClaw ESO Integration

**Files:**
- Create: `cluster/apps/openclaw/openclaw/app/github-secret-store.yaml`
- Create: `cluster/apps/openclaw/openclaw/app/github-external-secret.yaml`
- Modify: `cluster/apps/openclaw/openclaw/app/kustomization.yaml`

- [ ] **Step 1: Create github-secret-store.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/serviceaccount-v1.json
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-secret-reader
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/external-secrets.io/secretstore_v1.json
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: github-secret-store
spec:
  provider:
    kubernetes:
      remoteNamespace: github-system
      server:
        url: "https://kubernetes.default.svc"
        caProvider:
          type: ConfigMap
          name: kube-root-ca.crt
          key: ca.crt
      auth:
        serviceAccount:
          name: github-secret-reader
```

- [ ] **Step 2: Create github-external-secret.yaml**

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/external-secrets.io/externalsecret_v1.json
# Syncs write-tier access token to replace static GIT_CODE_TOKEN
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: github-bot-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: SecretStore
    name: github-secret-store
  target:
    name: github-bot-credentials
    creationPolicy: Owner
  data:
    - secretKey: GIT_CODE_TOKEN
      remoteRef:
        key: github-bot-credentials
        property: write-access-token
```

- [ ] **Step 3: Update openclaw app/kustomization.yaml**

Add the new resources to the existing kustomization.

- [ ] **Step 4: Update OpenClaw HelmRelease values**

OpenClaw loads `GIT_CODE_TOKEN` via `envFrom: [{secretRef: {name: openclaw-secrets}}]` (lines 35-37 and 101-103 of values.yaml). Explicit `env` entries take precedence over `envFrom`, so add an explicit env var sourcing from the new ESO-managed secret. This shadows the old value without needing to modify the SOPS file.

In `cluster/apps/openclaw/openclaw/app/values.yaml`, add to the `init-workspace` container (after the `envFrom` block around line 37) and to the main container (after its `envFrom` block around line 103):

```yaml
        env:
          GIT_CODE_TOKEN:
            valueFrom:
              secretKeyRef:
                name: github-bot-credentials
                key: GIT_CODE_TOKEN
```

This overrides the static `GIT_CODE_TOKEN` from `openclaw-secrets` with the auto-rotating token from ESO. The old key in `openclaw-secrets` can be removed later after verification.

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/github-secret-store.yaml \
  cluster/apps/openclaw/openclaw/app/github-external-secret.yaml \
  cluster/apps/openclaw/openclaw/app/kustomization.yaml \
  cluster/apps/openclaw/openclaw/app/values.yaml
git commit -m "feat(openclaw): migrate GIT_CODE_TOKEN to auto-rotating ESO secret

Replaces static PAT with write-tier OAuth token synced from
github-system via ESO cross-namespace sync.

Ref #829"
```

---

## Task 13: Monitoring (VMRule)

**Files:**
- Create: `cluster/apps/github-system/github-token-rotation/app/vmrule.yaml`
- Modify: `cluster/apps/github-system/github-token-rotation/app/kustomization.yaml`

- [ ] **Step 1: Create vmrule.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/operator.victoriametrics.com/vmrule_v1beta1.json
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMRule
metadata:
  name: github-token-rotation
spec:
  groups:
    - name: github-token-rotation
      rules:
        - alert: GitHubTokenRotationFailed
          expr: |
            kube_job_status_failed{namespace="github-system", job_name=~"github-token-rotation.*"} > 0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "GitHub token rotation CronJob failed"
            description: "CronJob {{ $labels.job_name }} failed. Current access tokens remain valid for up to 4 more hours."
        - alert: GitHubTokenRotationConsecutiveFailures
          expr: |
            time() - kube_cronjob_status_last_successful_time{namespace="github-system", cronjob="github-token-rotation"} > 28800
          labels:
            severity: critical
          annotations:
            summary: "GitHub token rotation has not succeeded in 8+ hours"
            description: "Access tokens have likely expired. Workloads using gh/git are degraded. Tokens will self-heal on next successful CronJob run."
```

- [ ] **Step 2: Add to kustomization.yaml**

Add `vmrule.yaml` to the resources list in `cluster/apps/github-system/github-token-rotation/app/kustomization.yaml`.

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/github-system/github-token-rotation/app/vmrule.yaml \
  cluster/apps/github-system/github-token-rotation/app/kustomization.yaml
git commit -m "feat(github-system): add VMRule alerts for token rotation failures

Ref #829"
```

---

## Task 14: Documentation + README

**Files:**
- Create: `cluster/apps/github-system/github-token-rotation/README.md`
- Create: `cluster/apps/github-mcp/github-mcp-server/README.md`
- Create: `cluster/apps/claude-agents-write/claude-agents/README.md`
- Create: `cluster/apps/claude-agents-read/claude-agents/README.md`

- [ ] **Step 1: Create READMEs**

Use the template from `docs/templates/readme_template.md`. Each README should cover:
- Overview (what it does, priority tier)
- Prerequisites (dependsOn items)
- Operation (key commands, how to trigger manual rotation, re-auth procedure)
- Troubleshooting (common issues: token expired, ESO sync failed, CronJob failure)
- References (GitHub App docs, ESO docs)

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/github-system/github-token-rotation/README.md \
  cluster/apps/github-mcp/github-mcp-server/README.md \
  cluster/apps/claude-agents-write/claude-agents/README.md \
  cluster/apps/claude-agents-read/claude-agents/README.md
git commit -m "docs: add READMEs for github-system, github-mcp, and claude-agents namespaces

Ref #829"
```

---

## Task 15: Run qa-validator

- [ ] **Step 1: Run qa-validator**

Run the qa-validator agent against all changed files before final commit/push.

- [ ] **Step 2: Fix any issues found**

Address linting, schema validation, or doc issues.

- [ ] **Step 3: Commit fixes if needed**

```bash
git commit -m "fix: address qa-validator findings

Ref #829"
```
