# GitHub MCP Auth Proxy Sidecar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an nginx auth-injecting reverse proxy sidecar to the github-mcp-server deployment so agent pods can connect without client-side credentials, and eliminate Reloader-triggered restarts from token rotation.

**Architecture:** An nginx sidecar container listens on port 8082 (the service port agents connect to), reads the GitHub PAT from a volume-mounted secret file, and proxies requests to the github-mcp-server container on port 8083 with `Authorization: Bearer <token>` injected. The secret is volume-mounted (not an env var) so kubelet auto-updates it without pod restarts. Reloader annotation is removed.

**Tech Stack:** nginx (alpine), bjw-s app-template Helm chart, Cilium network policies

**Linked Issue:** Ref #861

---

## File Map

| File | Action | Purpose |
| ---- | ------ | ------- |
| `cluster/apps/github-mcp/github-mcp-server/app/values.yaml` | Modify | Add auth-proxy sidecar container, change app port to 8083, add nginx ConfigMap and secret volume mounts, remove Reloader annotation, remove env var secretKeyRef |
| `cluster/apps/github-mcp/github-mcp-server/app/nginx-config.yaml` | Create | nginx/OpenResty ConfigMap with auth-injecting proxy config |
| `cluster/apps/github-mcp/github-mcp-server/app/kustomization.yaml` | Modify | Add nginx-config.yaml resource |
| `cluster/apps/github-mcp/github-mcp-server/app/vpa.yaml` | Modify | Add auth-proxy container policy |
| `cluster/apps/github-mcp/github-mcp-server/app/network-policies.yaml` | No change | Ingress policies match on pod labels, not container — sidecar is transparent |

---

### Task 1: Modify values.yaml — add auth-proxy sidecar and restructure ports

**Files:**
- Modify: `cluster/apps/github-mcp/github-mcp-server/app/values.yaml`

- [ ] **Step 1: Change github-mcp-server container port from 8082 to 8083**

The app container will now listen on 8083 (internal only). The sidecar takes over port 8082 (exposed via service).

In `values.yaml`, change the `args` and all probe ports from `8082` to `8083`:

```yaml
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
```

- [ ] **Step 2: Remove the env var and Reloader annotation**

Remove the `env` block from the `app` container (no longer needed — the app uses the token from the Authorization header injected by the proxy, not from its own env var).

Remove the Reloader annotation from the controller:

```yaml
controllers:
  github-mcp-server:
    strategy: Recreate
    # NOTE: reloader.stakater.com/auto annotation REMOVED
    containers:
      app:
        # NOTE: env block REMOVED — no GITHUB_PERSONAL_ACCESS_TOKEN needed
```

- [ ] **Step 3: Add the auth-proxy sidecar container**

Add a sibling container under `controllers.github-mcp-server.containers`:

```yaml
      auth-proxy:
        image:
          repository: openresty/openresty
          tag: 1.27.1.2-alpine@sha256:<verify-at-implementation>
          pullPolicy: IfNotPresent
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
            memory: 32Mi
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
```

> **Note:** OpenResty is used instead of plain nginx because `set_by_lua_block` is needed to read the token file on every request (picks up rotations without restart/reload). Verify the digest at implementation time:
> `docker pull openresty/openresty:1.27.1.2-alpine && docker inspect --format='{{index .RepoDigests 0}}' openresty/openresty:1.27.1.2-alpine`
> If 1.27.1.2 doesn't exist, use the latest stable alpine tag from Docker Hub.

- [ ] **Step 4: Add persistence volumes for nginx config, secret, and tmp/cache**

Add the following to the bottom of `values.yaml`:

```yaml
persistence:
  nginx-config:
    type: configMap
    name: github-mcp-nginx-config
    advancedMounts:
      github-mcp-server:
        auth-proxy:
          - path: /etc/nginx/nginx.conf
            subPath: nginx.conf
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
  nginx-tmp:
    type: emptyDir
    medium: Memory
    sizeLimit: 10Mi
    advancedMounts:
      github-mcp-server:
        auth-proxy:
          - path: /tmp
          - path: /var/cache/nginx
```

- [ ] **Step 5: Update the service to point at port 8082 on the auth-proxy**

The service already targets port 8082. Since the auth-proxy now owns that port, update the service to explicitly target the correct container port:

```yaml
service:
  app:
    controller: github-mcp-server
    ports:
      http:
        port: 8082
```

This remains unchanged — port 8082 is now served by the auth-proxy sidecar instead of the app container. No service change needed.

- [ ] **Step 6: Commit**

```bash
git add cluster/apps/github-mcp/github-mcp-server/app/values.yaml
git commit -m "feat(github-mcp): add auth-proxy sidecar, remove Reloader restart

Ref #861"
```

---

### Task 2: Create nginx ConfigMap with auth-injecting proxy config

**Files:**
- Create: `cluster/apps/github-mcp/github-mcp-server/app/nginx-config.yaml`
- Modify: `cluster/apps/github-mcp/github-mcp-server/app/kustomization.yaml`

- [ ] **Step 1: Create the nginx config ConfigMap**

Create `cluster/apps/github-mcp/github-mcp-server/app/nginx-config.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/configmap-v1.json
apiVersion: v1
kind: ConfigMap
metadata:
  name: github-mcp-nginx-config
data:
  nginx.conf: |
    worker_processes 1;
    error_log /tmp/error.log warn;
    pid /tmp/nginx.pid;

    events {
      worker_connections 64;
    }

    http {
      client_body_temp_path /tmp/client_body;
      proxy_temp_path /tmp/proxy;
      fastcgi_temp_path /tmp/fastcgi;
      uwsgi_temp_path /tmp/uwsgi;
      scgi_temp_path /tmp/scgi;

      server {
        listen 8082;
        server_name _;

        # Health check endpoint (no auth injection)
        location = /healthz {
          return 200 "ok";
          add_header Content-Type text/plain;
        }

        # MCP proxy with auth injection
        location / {
          # Read token from file on each request (picks up rotations)
          set_by_lua_block $github_token {
            local f = io.open("/etc/secrets/github-pat", "r")
            if f then
              local token = f:read("*a")
              f:close()
              return token:gsub("%s+$", "")
            end
            return ""
          }

          proxy_pass http://127.0.0.1:8083;
          proxy_set_header Authorization "Bearer $github_token";
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;

          # MCP streaming support
          proxy_http_version 1.1;
          proxy_set_header Connection "";
          proxy_buffering off;
          proxy_cache off;
          chunked_transfer_encoding on;

          # Generous timeouts for long MCP operations
          proxy_connect_timeout 10s;
          proxy_read_timeout 300s;
          proxy_send_timeout 300s;
        }
      }
    }
```

> **Note:** The `set_by_lua_block` directive requires the Lua module — this is why OpenResty is used (Task 1 Step 3) instead of plain nginx. OpenResty includes LuaJIT natively, enabling per-request token file reads that pick up rotations without restart/reload.

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
  - ./nginx-config.yaml
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
git add cluster/apps/github-mcp/github-mcp-server/app/nginx-config.yaml \
        cluster/apps/github-mcp/github-mcp-server/app/kustomization.yaml
git commit -m "feat(github-mcp): add nginx auth-proxy config with token file injection

Ref #861"
```

---

### Task 3: Update VPA for the new sidecar container

**Files:**
- Modify: `cluster/apps/github-mcp/github-mcp-server/app/vpa.yaml`

- [ ] **Step 1: Add containerPolicy for auth-proxy**

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
          memory: 32Mi
```

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/github-mcp/github-mcp-server/app/vpa.yaml
git commit -m "feat(github-mcp): add VPA policy for auth-proxy sidecar

Ref #861"
```

---

### Task 4: Remove the MCP config auth header for github (if present) and verify client config

**Files:**
- Verify: `cluster/apps/claude-agents-shared/base/claude-mcp-config.yaml`

- [ ] **Step 1: Verify no auth headers needed for github in MCP config**

Read `cluster/apps/claude-agents-shared/base/claude-mcp-config.yaml` and confirm the `github` entry has no `headers` block. Currently it looks like:

```json
"github": {
  "type": "http",
  "url": "http://github-mcp-server.github-mcp.svc:8082/mcp"
}
```

This is correct — no change needed. The auth-proxy sidecar injects the Authorization header server-side. Agent pods connect with no credentials.

- [ ] **Step 2: No commit needed** — no changes.

---

### Task 5: Validate and test

- [ ] **Step 1: Run qa-validator**

Run the qa-validator agent against all modified files before committing.

- [ ] **Step 2: Verify the nginx image tag and digest**

Look up the current stable OpenResty alpine image:

```bash
# Check latest OpenResty alpine tag
docker pull openresty/openresty:alpine
docker inspect --format='{{index .RepoDigests 0}}' openresty/openresty:alpine
```

Update the `auth-proxy` image tag and digest in `values.yaml` if needed.

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
