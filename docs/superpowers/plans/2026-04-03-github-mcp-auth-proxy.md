# GitHub MCP Auth Proxy Sidecar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Caddy auth-injecting reverse proxy sidecar to the github-mcp-server deployment so agent pods can connect without client-side credentials, and eliminate Reloader-triggered restarts from token rotation.

**Architecture:** A Caddy sidecar listens on port 8082 (service port), reads the GitHub PAT from a volume-mounted secret file via `{file.*}` placeholder, and proxies to port 8083 with `Authorization: Bearer <token>` injected. Volume-mounted secret auto-updates via kubelet without restarts. Reloader annotation removed.

**Tech Stack:** Caddy, bjw-s app-template Helm chart

**Linked Issue:** Ref #861

---

## File Map

| File | Action | Purpose |
| ---- | ------ | ------- |
| `cluster/apps/github-mcp/github-mcp-server/app/values.yaml` | Modify | Add auth-proxy sidecar, change app port to 8083, add Caddyfile and secret volume mounts, remove Reloader annotation and env var |
| `cluster/apps/github-mcp/github-mcp-server/app/caddy-config.yaml` | Create | ConfigMap with Caddyfile for auth-injecting reverse proxy |
| `cluster/apps/github-mcp/github-mcp-server/app/kustomization.yaml` | Modify | Add caddy-config.yaml resource |
| `cluster/apps/github-mcp/github-mcp-server/app/vpa.yaml` | Modify | Add auth-proxy container policy |
| `cluster/apps/github-mcp/github-mcp-server/app/network-policies.yaml` | No change | Ingress policies match on pod labels, not container — sidecar is transparent |

---

### Task 1: Create Caddyfile ConfigMap

**Files:**
- Create: `cluster/apps/github-mcp/github-mcp-server/app/caddy-config.yaml`
- Modify: `cluster/apps/github-mcp/github-mcp-server/app/kustomization.yaml`

- [ ] **Step 1: Create the Caddy config ConfigMap**

Create `cluster/apps/github-mcp/github-mcp-server/app/caddy-config.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/configmap-v1.json
apiVersion: v1
kind: ConfigMap
metadata:
  name: github-mcp-caddyfile
data:
  Caddyfile: |
    {
      admin off
      auto_https off
    }

    :8082 {
      handle /healthz {
        respond "ok" 200
      }

      handle {
        reverse_proxy 127.0.0.1:8083 {
          header_up Authorization "Bearer {file./etc/secrets/github-pat}"
          header_up Host {host}
          header_up X-Real-IP {remote_host}
          flush_interval -1
        }
      }
    }
```

> **Note:** `{file./etc/secrets/github-pat}` reads the token from disk on each request — picks up rotations automatically without restart or reload. `flush_interval -1` disables response buffering for MCP streaming support.

- [ ] **Step 2: Add the ConfigMap resource to kustomization.yaml**

In `cluster/apps/github-mcp/github-mcp-server/app/kustomization.yaml`, add the new resource:

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
  - ./caddy-config.yaml
configMapGenerator:
  - name: github-mcp-server-values
    namespace: github-mcp
    files:
      - values.yaml
configurations:
  - ./kustomizeconfig.yaml
```

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/github-mcp/github-mcp-server/app/caddy-config.yaml \
        cluster/apps/github-mcp/github-mcp-server/app/kustomization.yaml
git commit -m "feat(github-mcp): add Caddyfile config for auth-injecting proxy

Ref #861"
```

---

### Task 2: Modify values.yaml — add Caddy sidecar and restructure ports

**Files:**
- Modify: `cluster/apps/github-mcp/github-mcp-server/app/values.yaml`

- [ ] **Step 1: Rewrite values.yaml**

Replace the full contents of `values.yaml` with:

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
          tag: v0.33.0@sha256:a9dd39eec67f09ded51631c79641dd72acb4945c6391df47824fa2d508b5431b
          pullPolicy: IfNotPresent
        args:
          - "http"
          - "--port"
          - "8083"
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
                port: 8083
              initialDelaySeconds: 10
              periodSeconds: 30
              timeoutSeconds: 3
              failureThreshold: 3
          readiness:
            enabled: true
            custom: true
            spec:
              tcpSocket:
                port: 8083
              initialDelaySeconds: 5
              periodSeconds: 10
              timeoutSeconds: 3
              failureThreshold: 3
          startup:
            enabled: true
            custom: true
            spec:
              tcpSocket:
                port: 8083
              failureThreshold: 30
              periodSeconds: 5
      auth-proxy:
        image:
          repository: caddy
          tag: 2.9.1-alpine@sha256:<verify-at-implementation>
          pullPolicy: IfNotPresent
        args:
          - "caddy"
          - "run"
          - "--config"
          - "/etc/caddy/Caddyfile"
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
        resources:
          requests:
            cpu: 5m
            memory: 16Mi
          limits:
            memory: 64Mi
        probes:
          liveness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /healthz
                port: 8082
              periodSeconds: 30
              timeoutSeconds: 3
              failureThreshold: 3
          readiness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /healthz
                port: 8082
              periodSeconds: 10
              timeoutSeconds: 3
              failureThreshold: 3
          startup:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /healthz
                port: 8082
              failureThreshold: 30
              periodSeconds: 5
service:
  app:
    controller: github-mcp-server
    ports:
      http:
        port: 8082
persistence:
  caddyfile:
    type: configMap
    name: github-mcp-caddyfile
    advancedMounts:
      github-mcp-server:
        auth-proxy:
          - path: /etc/caddy/Caddyfile
            subPath: Caddyfile
            readOnly: true
  github-pat:
    type: secret
    name: github-mcp-credentials
    advancedMounts:
      github-mcp-server:
        auth-proxy:
          - path: /etc/secrets/github-pat
            subPath: GITHUB_PERSONAL_ACCESS_TOKEN
            readOnly: true
  caddy-data:
    type: emptyDir
    medium: Memory
    sizeLimit: 10Mi
    advancedMounts:
      github-mcp-server:
        auth-proxy:
          - path: /data
          - path: /config
```

Key changes from original:
- `annotations` block with `reloader.stakater.com/auto` — **removed**
- `env` block with `GITHUB_PERSONAL_ACCESS_TOKEN` secretKeyRef — **removed**
- `app` container port — changed from `8082` to `8083`
- `auth-proxy` container — **added** (Caddy sidecar on port 8082)
- `persistence` — **added** (Caddyfile, secret volume, emptyDir for Caddy runtime)

> **Note:** Verify the Caddy image digest at implementation time:
> `crane digest caddy:2.9.1-alpine`
> If 2.9.1 doesn't exist yet, use the latest stable 2.x alpine tag.

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/github-mcp/github-mcp-server/app/values.yaml
git commit -m "feat(github-mcp): add Caddy auth-proxy sidecar, remove Reloader restart

Ref #861"
```

---

### Task 3: Update VPA for the new sidecar container

**Files:**
- Modify: `cluster/apps/github-mcp/github-mcp-server/app/vpa.yaml`

- [ ] **Step 1: Add containerPolicy for auth-proxy**

Replace the full contents of `vpa.yaml` with:

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
      - containerName: auth-proxy
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          memory: 64Mi
```

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/github-mcp/github-mcp-server/app/vpa.yaml
git commit -m "feat(github-mcp): add VPA policy for auth-proxy sidecar

Ref #861"
```

---

### Task 4: Validate and test

- [ ] **Step 1: Verify Caddy image digest**

```bash
crane digest caddy:2.9.1-alpine
```

Update the `auth-proxy` image tag and digest in `values.yaml`.

- [ ] **Step 2: Run qa-validator**

Run the qa-validator agent against all modified/created files.

- [ ] **Step 3: After push, run cluster-validator**

After the user pushes to main, run the cluster-validator agent. Verify:
- The github-mcp-server deployment has 2 containers (app + auth-proxy)
- The auth-proxy is serving on port 8082
- The app container is on port 8083
- MCP handshake succeeds from an agent pod:

```bash
kubectl run mcp-auth-test --namespace=claude-agents-write \
  --image=ghcr.io/anthony-spruyt/claude-agent:1.1.1 \
  --labels="managed-by=n8n-claude-code" \
  --restart=Never --command -- sleep 120

kubectl wait --for=condition=Ready pod/mcp-auth-test -n claude-agents-write --timeout=60s

kubectl exec mcp-auth-test -n claude-agents-write -- \
  curl -s --max-time 10 -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' \
  "http://github-mcp-server.github-mcp.svc:8082/mcp"

# Expected: JSON-RPC response with serverInfo, NOT "Unauthorized"

kubectl delete pod mcp-auth-test -n claude-agents-write
```

- [ ] **Step 4: Verify token rotation doesn't restart the pod**

Wait for the next rotation cycle (runs every 30 min via CronJob `github-token-rotation`). Confirm:
- The github-mcp-server pod was NOT restarted (check `RESTARTS` column)
- The auth-proxy still injects a valid token (re-run the curl test above)
