# Nexus OSS for Coder Workspace Builds — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Sonatype Nexus Repository 3 OSS in-cluster via `bjw-s-labs/app-template` chart, scoped to Coder workspace builds and developer workstations, as an apt + docker artifact proxy + envbuilder kaniko layer cache.

**Architecture:** StatefulSet on `app-template` chart, 100Gi Ceph RBD PVC, plain HTTP `:8081` inside cluster (no Jetty TLS), Traefik terminates TLS externally, CoreDNS split-horizon via Talos `extraManifests`, configMapGenerator-hashed provisioning Job creates 10 repos + grants `nx-metrics-all` to anonymous.

**Tech Stack:** app-template 4.6.2 (already present as OCIRepository), Flux HelmRelease, cert-manager ZeroSSL, CoreDNS via Talos, Cilium CNP, standard Traefik IngressRoute, VictoriaMetrics VMPodScrape, VPA, SOPS for secrets.

**Reference:** `docs/superpowers/specs/2026-04-17-nexus-oss-coder-proxy-design.md`, issue [#968](https://github.com/anthony-spruyt/spruyt-labs/issues/968)

**Rollout:** 3 PRs. PR 1 = Tasks 1-9 (stack deployment). PR 2 = Tasks 10-12 (Coder integration). PR 3 = Task 13 (PAT cleanup).

---

## PR 1 — Nexus stack deployment

### Task 1: Create namespace

**Files:**
- Create: `cluster/apps/nexus-system/namespace.yaml`
- Create: `cluster/apps/nexus-system/kustomization.yaml`
- Modify: `cluster/apps/kustomization.yaml`

- [ ] **Step 1: Create namespace manifest** (follow `cluster/apps/qdrant-system/namespace.yaml` pattern)

```yaml
# cluster/apps/nexus-system/namespace.yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/core/namespace_v1.json
apiVersion: v1
kind: Namespace
metadata:
  name: nexus-system
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

- [ ] **Step 2: Create namespace kustomization**

```yaml
# cluster/apps/nexus-system/kustomization.yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./nexus/ks.yaml
```

- [ ] **Step 3: Register in top-level kustomization**

Append `- ./nexus-system` to `cluster/apps/kustomization.yaml` (ordering is not strictly alphabetical; append at end is fine).

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/nexus-system/namespace.yaml cluster/apps/nexus-system/kustomization.yaml cluster/apps/kustomization.yaml
git commit -m "feat(nexus): add nexus-system namespace

Ref #968"
```

---

### Task 2: Create SOPS secrets

**Files:**
- Create: `cluster/apps/nexus-system/nexus/app/nexus-admin.sops.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/nexus-upstream-creds.sops.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/nexus-envbuilder-credentials.sops.yaml`

- [ ] **Step 1: Generate admin password**

```bash
openssl rand -base64 24 | tr -d '/+=' | head -c 24
```

Nexus password must satisfy default policy (≥8 chars, mixed case, digit, special). If generated value fails, prepend e.g. `N3x!` manually.

- [ ] **Step 2: User creates admin secret via sops**

User runs:

```bash
sops cluster/apps/nexus-system/nexus/app/nexus-admin.sops.yaml
```

Unencrypted content:

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: nexus-admin
  namespace: nexus-system
type: Opaque
stringData:
  admin-username: "admin"
  admin-password: "<password-from-step-1>"
```

- [ ] **Step 3: User creates upstream creds secret**

Source values: extract dockerhub + ghcr credentials from the existing `ENVBUILDER_DOCKER_CONFIG_BASE64` entry in `cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml`. User handles extraction manually.

```bash
sops cluster/apps/nexus-system/nexus/app/nexus-upstream-creds.sops.yaml
```

Unencrypted content:

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: nexus-upstream-creds
  namespace: nexus-system
type: Opaque
stringData:
  dockerhub-username: "<existing-dockerhub-user>"
  dockerhub-token: "<existing-dockerhub-pat>"
  ghcr-username: "<existing-ghcr-user>"
  ghcr-token: "<existing-ghcr-pat>"
```

- [ ] **Step 4: User creates envbuilder docker config secret**

Used by Coder to authenticate to Nexus for cache pushes. Draft the `config.json` first:

```json
{
  "auths": {
    "nexus-docker.lan.${EXTERNAL_DOMAIN}": {
      "auth": "<base64 of admin:admin-password>"
    }
  }
}
```

> Note: for production, replace admin creds with a dedicated Nexus user scoped to `envbuilder-cache` push. Defer to a follow-up issue — admin is acceptable for initial rollout.

User creates a different SOPS file exposing the docker config as a raw value.
Envbuilder reads it from `ENVBUILDER_DOCKER_CONFIG_BASE64` env — the secret at
this step is not consumed by the cluster directly; it exists so the base64
value is stored once alongside the Nexus app. If preferred, skip this file and
store the dockerconfig inline in `coder-workspace-env.sops.yaml` (Task 10) —
either location works.

Recommend skipping the dedicated file; edit `coder-workspace-env.sops.yaml` directly in Task 10. Therefore this step is a no-op placeholder.

- [ ] **Step 5: Verify files are SOPS-encrypted**

```bash
head -20 cluster/apps/nexus-system/nexus/app/nexus-admin.sops.yaml
```

Expected: `sops:` block at bottom; data fields are `ENC[AES256_GCM,...]` strings.

- [ ] **Step 6: Commit**

```bash
git add cluster/apps/nexus-system/nexus/app/nexus-admin.sops.yaml cluster/apps/nexus-system/nexus/app/nexus-upstream-creds.sops.yaml
git commit -m "feat(nexus): add SOPS secrets for admin + upstream creds

Ref #968"
```

---

### Task 3: Create HelmRelease + app-template values

**Files:**
- Create: `cluster/apps/nexus-system/nexus/app/release.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/values.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/nexus-properties-configmap.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/kustomization.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/kustomizeconfig.yaml`
- Create: `cluster/apps/nexus-system/nexus/ks.yaml`

Pattern reference: `cluster/apps/vaultwarden/vaultwarden/app/` (same stateful app-template layout with PVC + reloader).

- [ ] **Step 1: Find latest Nexus 3 image digest**

```bash
Agent(description="Resolve Nexus 3 image", prompt="Find the latest stable sonatype/nexus3 image tag on Docker Hub (not -java8, not -java11-alpine — the default tag like '3.75.1'). Return tag + sha256 digest for linux/amd64.")
```

Record `sonatype/nexus3:<tag>@sha256:<digest>`.

- [ ] **Step 2: Create HelmRelease**

```yaml
# cluster/apps/nexus-system/nexus/app/release.yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nexus
spec:
  chartRef:
    kind: OCIRepository
    name: app-template
    namespace: flux-system
  interval: 4h
  valuesFrom:
    - kind: ConfigMap
      name: nexus-values
```

- [ ] **Step 3: Create nexus.properties ConfigMap**

```yaml
# cluster/apps/nexus-system/nexus/app/nexus-properties-configmap.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nexus-properties
  namespace: nexus-system
data:
  nexus.properties: |
    # Full replacement of default nexus.properties when mounted via subPath.
    # Keep HTTP-only — Traefik handles TLS externally.
    application-port=8081
    nexus.scripts.allowCreation=false
```

- [ ] **Step 4: Create values.yaml**

Schema: `https://raw.githubusercontent.com/bjw-s-labs/helm-charts/refs/tags/app-template-4.6.2/charts/library/common/values.schema.json`

```yaml
# cluster/apps/nexus-system/nexus/app/values.yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/refs/tags/app-template-4.6.2/charts/library/common/values.schema.json

defaultPodOptions:
  priorityClassName: standard-priority

controllers:
  main:
    type: statefulset
    annotations:
      reloader.stakater.com/auto: "true"
    pod:
      securityContext:
        runAsUser: 200
        runAsGroup: 200
        fsGroup: 200
        fsGroupChangePolicy: OnRootMismatch
        runAsNonRoot: true
    initContainers:
      permissions:
        image:
          repository: busybox
          tag: "1.37.0@sha256:1487d0af5f52b4ba31c7e465126ee2123fe3f2305d638e7827681e7cf6c83d5e"
        command:
          - sh
          - -c
          - |
            find /nexus-data -mindepth 1 -maxdepth 1 ! -name 'lost+found' -exec chown -R 200:200 {} \; || true
            if [ -d /nexus-data/lost+found ]; then
              chown 200:200 /nexus-data/lost+found 2>/dev/null || true
            fi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: [ALL]
            add: [CHOWN]
          runAsUser: 0
          runAsGroup: 0
          runAsNonRoot: false
        resources:
          requests: {cpu: 10m, memory: 16Mi}
          limits: {memory: 16Mi}
    containers:
      main:
        securityContext:
          runAsUser: 200
          runAsGroup: 200
          runAsNonRoot: true
          allowPrivilegeEscalation: false
          capabilities:
            drop: [ALL]
        image:
          # renovate: datasource=docker depName=sonatype/nexus3
          repository: sonatype/nexus3
          tag: "<tag-from-step-1>@sha256:<digest>"
        env:
          TZ: ${TIMEZONE}
          # Java heap + direct memory tuned for 4Gi limit
          INSTALL4J_ADD_VM_PARAMS: >-
            -Xms1200m -Xmx1200m
            -XX:MaxDirectMemorySize=2g
            -Dkaraf.startLocalConsole=false
          NEXUS_SECURITY_INITIAL_PASSWORD:
            valueFrom:
              secretKeyRef:
                name: nexus-admin
                key: admin-password
        probes:
          liveness: &probes
            enabled: true
            custom: true
            spec:
              httpGet: {path: /service/rest/v1/status, port: 8081}
              initialDelaySeconds: 60
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 5
          readiness: *probes
          startup:
            enabled: true
            custom: true
            spec:
              httpGet: {path: /service/rest/v1/status, port: 8081}
              initialDelaySeconds: 30
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 60   # allow up to 10 minutes for cold boot
        resources:
          requests: {cpu: 250m, memory: 2Gi}
          limits: {memory: 4Gi}

service:
  nexus:
    controller: main
    ports:
      http:
        port: 8081

persistence:
  data:
    type: persistentVolumeClaim
    accessMode: ReadWriteOnce
    size: 100Gi
    storageClass: rook-ceph-block
    globalMounts:
      - path: /nexus-data
  nexus-properties:
    type: configMap
    name: nexus-properties
    advancedMounts:
      main:
        main:
          - path: /nexus-data/etc/nexus.properties
            subPath: nexus.properties
            readOnly: true
  tmp:
    type: emptyDir
    globalMounts:
      - path: /tmp
```

> **Note:** If the initContainer `permissions` is redundant (app-template + fsGroup may handle it), remove it. Mirrors vaultwarden pattern for safety on RBD-formatted volumes.

- [ ] **Step 5: Create kustomizeconfig.yaml**

```yaml
# cluster/apps/nexus-system/nexus/app/kustomizeconfig.yaml
---
nameReference:
  - kind: ConfigMap
    version: v1
    fieldSpecs:
      - path: spec/valuesFrom/name
        kind: HelmRelease
```

- [ ] **Step 6: Create app kustomization**

```yaml
# cluster/apps/nexus-system/nexus/app/kustomization.yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./nexus-admin.sops.yaml
  - ./nexus-upstream-creds.sops.yaml
  - ./nexus-properties-configmap.yaml
  - ./release.yaml
  - ./provision-repos-rbac.yaml
  - ./provision-repos-job.yaml
  - ./network-policies.yaml
  - ./vpa.yaml
  - ./pod-monitor.yaml
configMapGenerator:
  - name: nexus-values
    namespace: nexus-system
    files:
      - values.yaml
  - name: nexus-provisioner-script
    namespace: nexus-system
    files:
      - provision.sh
configurations:
  - ./kustomizeconfig.yaml
```

- [ ] **Step 7: Create ks.yaml**

```yaml
# cluster/apps/nexus-system/nexus/ks.yaml
---
# yaml-language-server: $schema=https://k8s-schemas-cjso.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app nexus
  namespace: flux-system
spec:
  targetNamespace: nexus-system
  path: ./cluster/apps/nexus-system/nexus/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: cert-manager
    - name: kyverno
    - name: rook-ceph-cluster-storage
  prune: true
  timeout: 15m
  wait: true
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: nexus-ingress
  namespace: flux-system
spec:
  targetNamespace: nexus-system
  path: ./cluster/apps/traefik/traefik/ingress/nexus-system
  commonMetadata:
    labels:
      app.kubernetes.io/name: nexus-ingress
  dependsOn:
    - name: nexus
    - name: traefik
  prune: true
  timeout: 5m
  wait: true
```

- [ ] **Step 8: Validate build**

```bash
kubectl kustomize cluster/apps/nexus-system/nexus/app/ 2>&1 | head -60
```

Expected: renders without errors (some referenced resources — Job, RBAC, CNP, VPA, pod-monitor, provision.sh — don't exist yet; comment them out temporarily in app/kustomization.yaml if blocking, add back at each later task).

- [ ] **Step 9: Commit**

```bash
git add cluster/apps/nexus-system/nexus/app/release.yaml \
        cluster/apps/nexus-system/nexus/app/values.yaml \
        cluster/apps/nexus-system/nexus/app/nexus-properties-configmap.yaml \
        cluster/apps/nexus-system/nexus/app/kustomization.yaml \
        cluster/apps/nexus-system/nexus/app/kustomizeconfig.yaml \
        cluster/apps/nexus-system/nexus/ks.yaml
git commit -m "feat(nexus): add HelmRelease using app-template

Ref #968"
```

---

### Task 4: Create provisioning Job + RBAC + script ConfigMap

**Files:**
- Create: `cluster/apps/nexus-system/nexus/app/provision-repos-rbac.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/provision-repos-job.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/provision.sh`

The Job name is hash-suffixed via `configMapGenerator` referencing `provision.sh` — whenever script content changes, the ConfigMap hash changes, triggering Flux to re-create the Job (satisfies spec's "re-run on change" requirement).

- [ ] **Step 1: Create RBAC**

```yaml
# cluster/apps/nexus-system/nexus/app/provision-repos-rbac.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nexus-provisioner
  namespace: nexus-system
automountServiceAccountToken: false
```

No Role needed — Job receives all creds via `secretKeyRef` env injection (no API access required).

- [ ] **Step 2: Create provision.sh**

```bash
#!/bin/sh
# cluster/apps/nexus-system/nexus/app/provision.sh
set -eu

echo "Waiting for Nexus writable..."
for i in $(seq 1 60); do
  status=$(curl -sf -o /dev/null -w '%{http_code}' "${NEXUS_URL}/service/rest/v1/status/writable" || true)
  if [ "${status}" = "200" ]; then
    echo "Nexus writable"
    break
  fi
  echo "  attempt ${i}: HTTP ${status}, retrying in 10s..."
  sleep 10
done
test "${status}" = "200" || { echo "Nexus never became writable"; exit 1; }

AUTH="-u ${NEXUS_USER}:${NEXUS_PASSWORD}"
API="${NEXUS_URL}/service/rest/v1"

upsert() {
  local kind="$1" name="$2" body="$3"
  code=$(curl -sf -o /dev/null -w '%{http_code}' ${AUTH} "${API}/repositories/${name}" || echo 000)
  if [ "${code}" = "200" ]; then
    echo "  [${name}] exists, updating"
    curl -sf -X PUT -H "Content-Type: application/json" ${AUTH} \
      -d "${body}" "${API}/repositories/${kind}/${name}"
  else
    echo "  [${name}] creating"
    curl -sf -X POST -H "Content-Type: application/json" ${AUTH} \
      -d "${body}" "${API}/repositories/${kind}"
  fi
}

# --- apt proxies ---
upsert apt/proxy apt-ubuntu-proxy '{
  "name":"apt-ubuntu-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"http://archive.ubuntu.com/ubuntu/","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "apt":{"distribution":"jammy","flat":false}}'

for item in \
  "apt-cli-github https://cli.github.com/packages/ stable true" \
  "apt-nodesource https://deb.nodesource.com/ stable true" \
  "apt-hashicorp https://apt.releases.hashicorp.com/ jammy false" \
  "apt-launchpad https://ppa.launchpadcontent.net/ stable true" ; do
  set -- ${item}
  upsert apt/proxy "$1" '{
    "name":"'"$1"'","online":true,
    "storage":{"blobStoreName":"default","strictContentTypeValidation":false},
    "proxy":{"remoteUrl":"'"$2"'","contentMaxAge":1440,"metadataMaxAge":1440},
    "negativeCache":{"enabled":true,"timeToLive":1440},
    "httpClient":{"blocked":false,"autoBlock":true},
    "apt":{"distribution":"'"$3"'","flat":'"$4"'}}'
done

# --- docker proxies ---
upsert docker/proxy docker-hub-proxy '{
  "name":"docker-hub-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://registry-1.docker.io","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true,"authentication":{"type":"username","username":"'"${DOCKERHUB_USER}"'","password":"'"${DOCKERHUB_TOKEN}"'"}},
  "docker":{"v1Enabled":false,"forceBasicAuth":false},
  "dockerProxy":{"indexType":"HUB","cacheForeignLayers":false}}'

upsert docker/proxy ghcr-proxy '{
  "name":"ghcr-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://ghcr.io","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true,"authentication":{"type":"username","username":"'"${GHCR_USER}"'","password":"'"${GHCR_TOKEN}"'"}},
  "docker":{"v1Enabled":false,"forceBasicAuth":false},
  "dockerProxy":{"indexType":"REGISTRY","cacheForeignLayers":false}}'

upsert docker/proxy mcr-proxy '{
  "name":"mcr-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://mcr.microsoft.com","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "docker":{"v1Enabled":false,"forceBasicAuth":false},
  "dockerProxy":{"indexType":"REGISTRY","cacheForeignLayers":false}}'

upsert docker/hosted envbuilder-cache '{
  "name":"envbuilder-cache","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW"},
  "docker":{"v1Enabled":false,"forceBasicAuth":false}}'

upsert docker/group docker-group '{
  "name":"docker-group","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "group":{"memberNames":["docker-hub-proxy","ghcr-proxy","mcr-proxy","envbuilder-cache"]},
  "docker":{"v1Enabled":false,"forceBasicAuth":false}}'

# --- grant nx-metrics-all + nx-repository-view-*-*-read to anonymous role ---
echo "Configuring anonymous role..."
ANON_ROLE_JSON=$(curl -sf ${AUTH} "${API}/security/roles/anonymous")
echo "${ANON_ROLE_JSON}" | grep -q '"nx-metrics-all"' || {
  echo "  adding nx-metrics-all + repo-read privileges to anonymous"
  curl -sf -X PUT -H "Content-Type: application/json" ${AUTH} \
    -d '{
      "id":"anonymous","name":"Anonymous","description":"Anonymous user role",
      "privileges":["nx-repository-view-*-*-read","nx-repository-view-*-*-browse","nx-metrics-all","nx-healthcheck-read"],
      "roles":[]
    }' \
    "${API}/security/roles/anonymous"
}

# Ensure anonymous access is enabled globally
curl -sf -X PUT -H "Content-Type: application/json" ${AUTH} \
  -d '{"enabled":true,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}' \
  "${API}/security/anonymous"

echo "Provisioning complete."
```

- [ ] **Step 3: Create Job manifest**

```yaml
# cluster/apps/nexus-system/nexus/app/provision-repos-job.yaml
---
apiVersion: batch/v1
kind: Job
metadata:
  name: nexus-provision-repos
  namespace: nexus-system
  annotations:
    kustomize.toolkit.fluxcd.io/force: "true"
spec:
  ttlSecondsAfterFinished: 3600
  backoffLimit: 10
  template:
    metadata:
      labels:
        app.kubernetes.io/name: nexus-provisioner
    spec:
      serviceAccountName: nexus-provisioner
      restartPolicy: OnFailure
      securityContext:
        runAsUser: 65534
        runAsGroup: 65534
        runAsNonRoot: true
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: provisioner
          # renovate: datasource=docker depName=curlimages/curl
          image: curlimages/curl:8.10.1
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: [ALL]}
            readOnlyRootFilesystem: true
          env:
            - name: NEXUS_URL
              value: "http://nexus.nexus-system.svc.cluster.local:8081"
            - name: NEXUS_USER
              valueFrom: {secretKeyRef: {name: nexus-admin, key: admin-username}}
            - name: NEXUS_PASSWORD
              valueFrom: {secretKeyRef: {name: nexus-admin, key: admin-password}}
            - name: DOCKERHUB_USER
              valueFrom: {secretKeyRef: {name: nexus-upstream-creds, key: dockerhub-username}}
            - name: DOCKERHUB_TOKEN
              valueFrom: {secretKeyRef: {name: nexus-upstream-creds, key: dockerhub-token}}
            - name: GHCR_USER
              valueFrom: {secretKeyRef: {name: nexus-upstream-creds, key: ghcr-username}}
            - name: GHCR_TOKEN
              valueFrom: {secretKeyRef: {name: nexus-upstream-creds, key: ghcr-token}}
          command: ["/bin/sh", "/scripts/provision.sh"]
          volumeMounts:
            - {name: script, mountPath: /scripts, readOnly: true}
      volumes:
        - name: script
          configMap:
            name: nexus-provisioner-script
            defaultMode: 0755
```

The ConfigMap name `nexus-provisioner-script` is hash-suffixed by `configMapGenerator` (Task 3 Step 6) — Kustomize name-reference rewrites the volume's `configMap.name` to the hashed version automatically. When `provision.sh` changes, the new hash triggers Flux to re-apply, and the `force: "true"` annotation causes the Job to be recreated.

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/nexus-system/nexus/app/provision-repos-rbac.yaml \
        cluster/apps/nexus-system/nexus/app/provision-repos-job.yaml \
        cluster/apps/nexus-system/nexus/app/provision.sh
git commit -m "feat(nexus): add REST-API provisioning Job with hashed script

Ref #968"
```

---

### Task 5: Create NetworkPolicy, VPA, VMPodScrape

**Files:**
- Create: `cluster/apps/nexus-system/nexus/app/network-policies.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/vpa.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/pod-monitor.yaml`

- [ ] **Step 1: CiliumNetworkPolicy**

```yaml
# cluster/apps/nexus-system/nexus/app/network-policies.yaml
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: nexus-default
  namespace: nexus-system
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: nexus
  ingress:
    - fromEndpoints:
        - matchLabels: {k8s:io.kubernetes.pod.namespace: coder-system}
      toPorts:
        - ports: [{port: "8081", protocol: TCP}]
    - fromEndpoints:
        - matchLabels: {k8s:io.kubernetes.pod.namespace: traefik}
      toPorts:
        - ports: [{port: "8081", protocol: TCP}]
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            k8s:app.kubernetes.io/name: vmagent
      toPorts:
        - ports: [{port: "8081", protocol: TCP}]
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: nexus-system
            k8s:app.kubernetes.io/name: nexus-provisioner
      toPorts:
        - ports: [{port: "8081", protocol: TCP}]
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - {port: "53", protocol: UDP}
            - {port: "53", protocol: TCP}
          rules:
            dns:
              - matchPattern: "*"
    - toEntities: ["world"]
      toPorts:
        - ports:
            - {port: "443", protocol: TCP}
            - {port: "80", protocol: TCP}
```

- [ ] **Step 2: VPA**

```yaml
# cluster/apps/nexus-system/nexus/app/vpa.yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: nexus
  namespace: nexus-system
spec:
  targetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: nexus
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: main
        minAllowed: {cpu: 1m, memory: 1Mi}
        maxAllowed: {memory: 4Gi}
```

app-template names the container `main` (per `containers.main` in values.yaml Task 3 Step 4).

- [ ] **Step 3: VMPodScrape**

```yaml
# cluster/apps/nexus-system/nexus/app/pod-monitor.yaml
---
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMPodScrape
metadata:
  name: nexus
  namespace: nexus-system
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: nexus
  podMetricsEndpoints:
    - port: http
      path: /service/metrics/prometheus
      interval: 60s
      scrapeTimeout: 30s
```

No basic auth — provisioning Job grants `nx-metrics-all` to anonymous.

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/nexus-system/nexus/app/network-policies.yaml \
        cluster/apps/nexus-system/nexus/app/vpa.yaml \
        cluster/apps/nexus-system/nexus/app/pod-monitor.yaml
git commit -m "feat(nexus): add CNP, VPA, and metrics scrape

Ref #968"
```

---

### Task 6: Add CoreDNS rewrite via Talos extraManifests

**Files:**
- Modify: `talos/talconfig.yaml` (or create new manifest under `talos/`)

- [ ] **Step 1: Locate Talos CoreDNS handling**

```bash
Grep pattern="coreDNS|coredns|extraManifests" path="talos/talconfig.yaml" output_mode="content" -n=true
```

Expected finding: either (a) `extraManifests:` key with a list of URLs or local paths, or (b) no explicit CoreDNS override (Talos default).

- [ ] **Step 2: Create CoreDNS Corefile override manifest**

```yaml
# talos/manifests/coredns-rewrite.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
      errors
      health {
        lameduck 5s
      }
      ready
      rewrite name exact nexus.lan.${EXTERNAL_DOMAIN} nexus.nexus-system.svc.cluster.local
      rewrite name exact nexus-docker.lan.${EXTERNAL_DOMAIN} nexus.nexus-system.svc.cluster.local
      kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 30
      }
      prometheus :9153
      forward . /etc/resolv.conf {
        max_concurrent 1000
      }
      cache 30
      loop
      reload
      loadbalance
    }
```

> **CRITICAL:** `${EXTERNAL_DOMAIN}` in Talos manifests is NOT substituted by Flux (Talos applies the manifest directly). Either:
> - **a)** Hardcode the literal domain value in this Corefile (violates "no hardcoded domains" rule — but the rule scope is `cluster/`, not `talos/`)
> - **b)** Use Talos machine config patches that allow env var substitution at config generation time
> - **c)** Use Talos's `cluster.coreDNS.extraDomains` or similar option if available
>
> **Recommended:** Pre-flight decision — check `talos/talenv.sops.yaml` / `talos/talconfig.yaml` for an existing pattern of domain substitution, or hardcode in `talos/` since that's outside the `cluster/` scope.
> Also: the exact default Corefile (rest of the plugins) must match what Talos currently ships to avoid accidentally dropping required plugins. Diff against the running Corefile:
>
> ```bash
> mcp__kubernetes__get_configmaps namespace=kube-system
> # Then get the specific one's Corefile
> ```
> Adjust the manifest to preserve all existing plugin blocks.

- [ ] **Step 3: Reference manifest in talconfig.yaml**

Add under the relevant `node` or global `extraManifests` section:

```yaml
extraManifests:
  - "./manifests/coredns-rewrite.yaml"
```

- [ ] **Step 4: Regenerate + apply Talos configs**

Per `.claude/memory/feedback_talos_genconfig.md`:

```bash
cd talos
task talos:genconfig   # or equivalent task exposed in .taskfiles/
# Then per-node: talosctl apply-config -n <node> -f clusterconfig/<node>.yaml
```

- [ ] **Step 5: Verify**

```bash
mcp__kubernetes__exec_in_pod namespace=kube-system pod=<coredns-pod> command=["cat","/etc/coredns/Corefile"]
```

Expected: rewrite lines present.

Test from a scratch pod:

```bash
mcp__kubernetes__run_pod namespace=default image=busybox command=["nslookup","nexus.lan.<literal-domain>"]
```

Expected: resolves to Nexus ClusterIP (once Task 3 HelmRelease is deployed; otherwise NXDOMAIN-but-rewrite-visible).

- [ ] **Step 6: Commit**

```bash
git add talos/manifests/coredns-rewrite.yaml talos/talconfig.yaml
git commit -m "feat(talos): add CoreDNS rewrite for nexus FQDNs

Ref #968"
```

---

### Task 7: Add Traefik IngressRoute

**Files:**
- Create: `cluster/apps/traefik/traefik/ingress/nexus-system/kustomization.yaml`
- Create: `cluster/apps/traefik/traefik/ingress/nexus-system/certificates.yaml`
- Create: `cluster/apps/traefik/traefik/ingress/nexus-system/ingress-routes.yaml`

Pattern: mirror `cluster/apps/traefik/traefik/ingress/vaultwarden/`. LAN-only apps use `.lan.${EXTERNAL_DOMAIN}` + `lan-ip-whitelist` middleware per `.claude/rules/06-ingress-and-certificates.md`.

- [ ] **Step 1: Create certificate**

```yaml
# cluster/apps/traefik/traefik/ingress/nexus-system/certificates.yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/cert-manager.io/certificate_v1.json
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nexus
  namespace: nexus-system
spec:
  secretName: "nexus-${EXTERNAL_DOMAIN/./-}-tls"
  issuerRef:
    name: ${CLUSTER_ISSUER}
    kind: ClusterIssuer
  dnsNames:
    - nexus.lan.${EXTERNAL_DOMAIN}
    - nexus-docker.lan.${EXTERNAL_DOMAIN}
```

> **Note:** `${CLUSTER_ISSUER}` resolves to `zerossl-production` via substitution from `cluster-settings` ConfigMap.

- [ ] **Step 2: Create IngressRoute**

```yaml
# cluster/apps/traefik/traefik/ingress/nexus-system/ingress-routes.yaml
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: nexus-ui
  namespace: nexus-system
  annotations:
    external-dns.alpha.kubernetes.io/hostname: nexus.lan.${EXTERNAL_DOMAIN}
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`nexus.lan.${EXTERNAL_DOMAIN}`)
      kind: Rule
      middlewares:
        - {name: lan-ip-whitelist, namespace: traefik}
        - {name: compress, namespace: traefik}
      services:
        - name: nexus
          namespace: nexus-system
          passHostHeader: true
          port: 8081
  tls:
    secretName: "nexus-${EXTERNAL_DOMAIN/./-}-tls"
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: nexus-docker
  namespace: nexus-system
  annotations:
    external-dns.alpha.kubernetes.io/hostname: nexus-docker.lan.${EXTERNAL_DOMAIN}
spec:
  entryPoints: [websecure]
  routes:
    # docker client path: /v2/* → rewrite to /repository/docker-group/v2/*
    - match: Host(`nexus-docker.lan.${EXTERNAL_DOMAIN}`) && PathPrefix(`/v2`)
      kind: Rule
      middlewares:
        - {name: lan-ip-whitelist, namespace: traefik}
        - {name: nexus-docker-prefix, namespace: nexus-system}
      services:
        - name: nexus
          namespace: nexus-system
          passHostHeader: true
          port: 8081
  tls:
    secretName: "nexus-${EXTERNAL_DOMAIN/./-}-tls"
---
# Path-prefix middleware so docker client's `/v2/...` hits `/repository/docker-group/v2/...`
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: nexus-docker-prefix
  namespace: nexus-system
spec:
  addPrefix:
    prefix: /repository/docker-group
```

> **Verification needed during rollout:** Sonatype's reverse-proxy docker
> strategy may prefer a different prefix mapping (e.g. a dedicated docker
> connector port). The middleware approach above works for most clients but
> test with `docker pull nexus-docker.lan.<domain>/alpine:3` after deployment.
> If broken, fall back to configuring a docker connector on the `docker-group`
> repository itself (`docker.httpPort` field) and route by host+subdomain to
> that port.

- [ ] **Step 3: Create kustomization**

```yaml
# cluster/apps/traefik/traefik/ingress/nexus-system/kustomization.yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./certificates.yaml
  - ./ingress-routes.yaml
```

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/traefik/traefik/ingress/nexus-system/
git commit -m "feat(nexus): add Traefik ingress + TLS cert

Ref #968"
```

---

### Task 8: Add README.md

**Files:**
- Create: `cluster/apps/nexus-system/nexus/README.md`

Per `.claude/rules/documentation.md`, new app components require README.md before merge. Use `docs/templates/readme_template.md` as base.

- [ ] **Step 1: Read template**

```bash
Read file_path="/workspaces/spruyt-labs/docs/templates/readme_template.md"
```

(If template missing, mirror an existing README: `cluster/apps/qdrant-system/qdrant/README.md`.)

- [ ] **Step 2: Write README covering:**

- Overview (Nexus 3 OSS for Coder envbuilder apt + docker cache)
- Prerequisites (`dependsOn` from ks.yaml: cert-manager, kyverno, rook-ceph-cluster-storage)
- Operation (common kubectl commands, how to log into UI, how to rotate admin password)
- Troubleshooting (provisioning Job stuck, blob store full, cert renewal, apt proxy upstream down)
- References (spec link, issue link, Sonatype docs)

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/nexus-system/nexus/README.md
git commit -m "docs(nexus): add README

Ref #968"
```

---

### Task 9: Validate + push PR 1

- [ ] **Step 1: Run qa-validator**

Dispatch qa-validator agent per `.claude/rules/02-validation.md`. Fix anything BLOCKING. Per `feedback_run_megalinter_local.md`, also run locally before push:

```bash
task dev-env:lint
```

- [ ] **Step 2: Push branch + open PR**

```bash
git push -u origin <branch>
gh pr create --repo anthony-spruyt/spruyt-labs \
  --title "feat(nexus): deploy Sonatype Nexus OSS (stack only, no consumers)" \
  --body "$(cat <<'EOF'
## Summary
Deploy in-cluster Nexus 3 OSS as apt + docker proxy cache for Coder workspace builds.
Stack-only — no consumer changes yet. Next PR wires envbuilder.

## Linked Issue
Ref #968

## Changes
- Namespace `nexus-system`, app-template HelmRelease, 100Gi ceph-block PVC
- 10 repos provisioned via hashed Job: apt (5), docker proxy (3), hosted cache (1), group (1)
- Anonymous access for reads + metrics
- Traefik ingress with ZeroSSL cert at `nexus.lan.$DOMAIN` + `nexus-docker.lan.$DOMAIN`
- CoreDNS rewrite via Talos `extraManifests` for in-cluster split-horizon
- CNP, VPA (rec-only), VMPodScrape

## Testing
- [ ] qa-validator pass
- [ ] After merge: cluster-validator verdict
- [ ] Manual UI login from dev PC
- [ ] Smoke apt pull through `nexus.lan`
- [ ] Smoke docker pull through `nexus-docker.lan`
EOF
)"
```

- [ ] **Step 3: User merges PR**

- [ ] **Step 4: Run cluster-validator**

Verify:
- `nexus-system` namespace exists, PSA `restricted`
- StatefulSet `nexus` Ready (1/1)
- PVC bound at 100Gi
- Certificate `nexus` Ready, cert mounted on Traefik
- Provisioning Job completed
- UI reachable: `curl -v https://nexus.lan.<domain>` returns 200 with valid cert
- Smoke apt: `curl -v https://nexus.lan.<domain>/repository/apt-ubuntu-proxy/dists/jammy/Release` returns 200
- Smoke docker: `docker pull nexus-docker.lan.<domain>/alpine:3` succeeds

If any fails, triage per cluster-validator output.

---

## PR 2 — Coder integration

### Task 10: Update coder-workspace-env.sops.yaml

**Files:**
- Modify: `cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml`

- [ ] **Step 1: Draft new docker config.json**

```json
{
  "auths": {
    "nexus-docker.lan.${EXTERNAL_DOMAIN}": {
      "auth": "<base64 of admin:admin-password>"
    }
  }
}
```

(Replace admin creds with a dedicated Nexus user in a follow-up issue.)

- [ ] **Step 2: User edits sops file**

```bash
sops cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml
```

Changes:
- `ENVBUILDER_DOCKER_CONFIG_BASE64` → base64 of the new config.json from Step 1
- Add `KANIKO_REGISTRY_MIRROR: "nexus-docker.lan.<literal-domain>/repository/docker-group"` (Coder's env rendering substitutes `${EXTERNAL_DOMAIN}` if supported; otherwise hardcode the literal domain here since it's in SOPS encrypted at rest)
- **Leave** the old upstream dockerhub/ghcr PATs in place — Task 13 removes them after stability confirmed.

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml
git commit -m "feat(coder): route envbuilder pulls through Nexus via KANIKO_REGISTRY_MIRROR

Ref #968"
```

---

### Task 11: Update Coder devcontainer template

**Files:**
- Modify: `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf`
- Create/Modify: devcontainer Dockerfile in the same directory (if template bakes one)

- [ ] **Step 1: Locate current cache repo line**

```bash
Grep pattern="ENVBUILDER_CACHE_REPO" path="cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf" -n=true output_mode="content"
```

- [ ] **Step 2: Replace ENVBUILDER_CACHE_REPO**

```hcl
# main.tf, around line 58
"ENVBUILDER_CACHE_REPO" : "nexus-docker.lan.${var.external_domain}/repository/envbuilder-cache/${data.coder_workspace.me.name}",
```

Add in same env map:

```hcl
"KANIKO_REGISTRY_MIRROR" : "nexus-docker.lan.${var.external_domain}/repository/docker-group",
```

Verify `var.external_domain` exists. If not, declare:

```hcl
variable "external_domain" {
  type        = string
  description = "Cluster external domain for in-cluster FQDNs"
}
```

and wire into the module call upstream.

- [ ] **Step 3: Check for template Dockerfile**

```bash
Glob pattern="cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/**/Dockerfile"
```

- [ ] **Step 4: If Dockerfile exists, add apt proxy**

```dockerfile
# Added to Coder devcontainer template Dockerfile
RUN echo 'Acquire::https::Proxy "https://nexus.lan.${external_domain}/repository/apt-ubuntu-proxy/";' \
    > /etc/apt/apt.conf.d/01proxy
```

Where `${external_domain}` is substituted by Terraform at template render time.

For HTTPS-upstream apt features (nodesource, hashicorp, cli.github, launchpad), add per-feature `sources.list.d/*.list` pointing at the corresponding passthrough proxy. This is a larger change — capture in the README for the template and implement per need.

- [ ] **Step 5: If no template Dockerfile, defer to per-repo**

Document in template README that consumer repos (this one included) should add their own `.devcontainer/Dockerfile` apt proxy via build ARG (out of scope for #968).

- [ ] **Step 6: Commit**

```bash
git add cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf
git commit -m "feat(coder): point envbuilder cache + mirror at Nexus

Ref #968"
```

---

### Task 12: Validate Coder rebuild end-to-end

- [ ] **Step 1: Push + merge PR 2**

```bash
gh pr create --repo anthony-spruyt/spruyt-labs --title "feat(coder): route envbuilder through Nexus"
```

Body references #968.

- [ ] **Step 2: Run cluster-validator**

- [ ] **Step 3: Rebuild one test Coder workspace manually**

- [ ] **Step 4: Inspect envbuilder logs**

```bash
mcp__kubernetes__get_logs namespace=coder-system pod=<envbuilder-pod>
```

Expected evidence:
- Kaniko shows `Using registry mirror: nexus-docker.lan.<domain>/repository/docker-group`
- Base image pulls show the Nexus hostname
- Cache push to `nexus-docker.lan.<domain>/repository/envbuilder-cache/<workspace>`

- [ ] **Step 5: Verify Nexus blob store growth**

```bash
curl -u admin:<password> https://nexus.lan.<domain>/service/rest/v1/blobstores/default/quota-status
```

Blob count + size should increase.

- [ ] **Step 6: Rebuild 2 more workspaces for stability signal**

Goal: 3+ successful rebuilds per `feedback_no_observation_windows.md` (replace time-based observation with concrete success count).

---

## PR 3 — Cleanup

### Task 13: Remove upstream PATs from coder-workspace-env

**Files:**
- Modify: `cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml`

- [ ] **Step 1: Confirm 3+ rebuild signal**

Check VM dashboard for Nexus uptime + no workspace build failures attributed to upstream rate-limit in the past 3 rebuilds.

- [ ] **Step 2: Edit SOPS file**

```bash
sops cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml
```

Remove dockerhub + ghcr PAT env vars now relocated to `nexus-upstream-creds` in Nexus.

- [ ] **Step 3: Commit + PR**

```bash
git add cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml
git commit -m "chore(coder): remove upstream PATs migrated to Nexus

Closes #968"

gh pr create --repo anthony-spruyt/spruyt-labs --title "chore(coder): remove legacy upstream PATs (Closes #968)"
```

- [ ] **Step 4: Cluster-validator after merge + one more rebuild to confirm**

- [ ] **Step 5: Close issue**

```bash
gh issue close 968 --repo anthony-spruyt/spruyt-labs \
  --comment "Completed via PRs <N>, <N+1>, <N+2>. Nexus deployed, Coder workspaces routed through it, legacy PATs removed."
```

---

## Runbook notes (captured during plan authoring)

1. **Admin password rotation.** `NEXUS_SECURITY_INITIAL_PASSWORD` applies only on first-boot with empty PVC. After initial setup, rotate via Nexus REST API (`PUT /service/rest/v1/security/users/admin/change-password`) AND update `nexus-admin` SOPS secret. The provisioning Job reads `admin-password` env each run — if stale, it will 401; address by manually running the rotation before a Job re-run.

2. **Blob store full.** Online PVC expansion: `kubectl patch pvc data-nexus-0 -n nexus-system -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'`. Ceph RBD resizes live; Nexus picks up the new size without restart.

3. **Docker path-prefix middleware verification.** Task 7 Step 2 introduces
   `nexus-docker-prefix` middleware rewriting `/v2/*` → `/repository/docker-group/v2/*`.
   If docker clients 404, fall back to configuring `docker-group.docker.httpPort`
   in the provisioning Job JSON and exposing a second service port — reverts to
   the multi-port complexity. Validate early in PR 1 post-deploy smoke tests.

4. **CoreDNS bootstrap risk.** Task 6 modifies the CoreDNS ConfigMap via Talos.
   A mistake here (invalid Corefile, missing `kubernetes` plugin) could break
   cluster DNS entirely. Mitigation: keep a backup of the current Corefile
   (`kubectl get cm -n kube-system coredns -o yaml > /tmp/corefile-backup.yaml`)
   before applying, and test the new Corefile with `coredns -conf` locally first
   if possible.
