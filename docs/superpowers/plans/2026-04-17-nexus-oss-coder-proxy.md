# Nexus OSS for Coder Workspace Builds — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Sonatype Nexus Repository 3 OSS in-cluster via `bjw-s-labs/app-template`, scoped to Coder workspace builds + developer workstations, as apt + docker artifact proxy + envbuilder kaniko layer cache.

**Architecture:** StatefulSet on app-template, 100Gi Ceph RBD PVC,
multi-port Service (8081 apt/UI/REST, 8082 docker-group connector, 8083
envbuilder-cache connector). Plain HTTP inside cluster — workspace pods
hit `nexus.nexus-system.svc.cluster.local` directly with
`ENVBUILDER_INSECURE=true`. Traefik terminates TLS with ZeroSSL cert for
dev PC access only. configMapGenerator-hashed provisioning Job creates
10 repos + grants `nx-metrics-all` to anonymous via GET-merge-PUT.

**Tech Stack:** app-template 4.6.2 OCIRepository (existing), Flux HelmRelease, cert-manager ZeroSSL, Cilium CNP, Traefik IngressRoute, VMPodScrape, VPA, SOPS.

**Reference:** `docs/superpowers/specs/2026-04-17-nexus-oss-coder-proxy-design.md`, issue [#968](https://github.com/anthony-spruyt/spruyt-labs/issues/968)

**Rollout:** 3 PRs. PR 1 = Tasks 1-8 (stack). PR 2 = Tasks 9-11 (Coder integration). PR 3 = Task 12 (PAT cleanup).

**Verified pre-flight findings** (from research + repo grep):
- `CLUSTER_ISSUER=zerossl-production` (in `cluster/flux/meta/cluster-settings.yaml`)
- `rook-ceph-cluster-storage` is the Kustomization owning `rook-ceph-block` StorageClass
- `app-template` OCIRepository present at tag `4.6.2`
- Workspace envbuilder pods carry label `com.coder.resource: "true"` (Terraform template sets it)
- Talos default CoreDNS NOT customized (confirmed — and intentionally not modified in this plan)

---

## PR 1 — Nexus stack

### Task 1: Create namespace

**Files:**
- Create: `cluster/apps/nexus-system/namespace.yaml`
- Create: `cluster/apps/nexus-system/kustomization.yaml`
- Modify: `cluster/apps/kustomization.yaml`

- [ ] **Step 1: Create namespace**

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

- [ ] **Step 2: Namespace kustomization**

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

Insert `- ./nexus-system` alphabetically between `./n8n-system` and `./nut-system` in `cluster/apps/kustomization.yaml` (the file is sorted alphabetically per repo convention).

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

- [ ] **Step 1: Generate admin password**

```bash
openssl rand -base64 24 | tr -d '/+=' | head -c 24
```

Nexus default policy requires ≥8 chars with mixed case/digit/special. If generated value doesn't satisfy, prefix with `N3x!`.

- [ ] **Step 2: User creates admin SOPS secret**

```bash
sops cluster/apps/nexus-system/nexus/app/nexus-admin.sops.yaml
```

Content (unencrypted form):

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

- [ ] **Step 3: User creates upstream creds SOPS secret**

Source: extract existing dockerhub + ghcr credentials from `ENVBUILDER_DOCKER_CONFIG_BASE64` in `cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml`. User handles extraction manually.

```bash
sops cluster/apps/nexus-system/nexus/app/nexus-upstream-creds.sops.yaml
```

Content:

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

- [ ] **Step 4: Verify encryption**

```bash
head -20 cluster/apps/nexus-system/nexus/app/nexus-admin.sops.yaml
```

Expected: `sops:` block at bottom; data fields are `ENC[AES256_GCM,...]`.

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/nexus-system/nexus/app/nexus-admin.sops.yaml cluster/apps/nexus-system/nexus/app/nexus-upstream-creds.sops.yaml
git commit -m "feat(nexus): add SOPS secrets for admin + upstream creds

Ref #968"
```

---

### Task 3: HelmRelease + app-template values

**Files:**
- Create: `cluster/apps/nexus-system/nexus/app/release.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/values.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/nexus-properties-configmap.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/kustomization.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/kustomizeconfig.yaml`
- Create: `cluster/apps/nexus-system/nexus/ks.yaml`

Reference: `cluster/apps/vaultwarden/vaultwarden/app/` is the closest structural exemplar (StatefulSet + PVC + reloader with app-template).

- [ ] **Step 1: Find latest `sonatype/nexus3` tag + digest**

Research: open a short-lived session via Context7 (`resolve-library-id` for `sonatype/nexus3`) or query Docker Hub:

```bash
curl -s "https://registry.hub.docker.com/v2/repositories/sonatype/nexus3/tags?page_size=25" \
  | jq -r '.results[] | select(.name | test("^3\\.[0-9]+\\.[0-9]+$")) | .name' \
  | head -5
```

Take the newest stable tag (e.g., `3.75.1`). Get the amd64 digest:

```bash
docker buildx imagetools inspect sonatype/nexus3:3.75.1 --format '{{json .Manifest}}'
```

Record `sonatype/nexus3:<tag>@sha256:<digest>` for Step 4.

- [ ] **Step 2: Create HelmRelease** (minimal form matching vaultwarden's release.yaml verbatim pattern)

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

- [ ] **Step 3: Create nexus-properties ConfigMap** (plain resource, not hashed — reloader handles updates by name)

```yaml
# cluster/apps/nexus-system/nexus/app/nexus-properties-configmap.yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/core/configmap_v1.json
apiVersion: v1
kind: ConfigMap
metadata:
  name: nexus-properties
  namespace: nexus-system
data:
  nexus.properties: |
    # Full replacement: default nexus.properties is shadowed by subPath mount.
    # HTTP-only on :8081. Docker connector runs on :8082 (configured per-repo).
    # nexus.base.url drives absolute URLs in docker realm + apt Release files —
    # must match the externally-visible scheme (https via Traefik).
    application-port=8081
    nexus.base.url=https://nexus.lan.${EXTERNAL_DOMAIN}
    nexus.scripts.allowCreation=false
```

- [ ] **Step 4: Create values.yaml**

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
          TZ:
            value: "${TIMEZONE}"
          INSTALL4J_ADD_VM_PARAMS:
            value: "-Xms1200m -Xmx1200m -XX:MaxDirectMemorySize=2g -Dkaraf.startLocalConsole=false"
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
              failureThreshold: 60
        resources:
          requests: {cpu: 250m, memory: 2Gi}
          limits: {memory: 4Gi}

service:
  nexus:
    controller: main
    ports:
      http:
        port: 8081
      docker-group:
        port: 8082
      docker-cache:
        port: 8083

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

> **env shape note:** Map form with wrapped `value:` / `valueFrom:` —
> bjw-s app-template convention. See
> `cluster/apps/n8n-system/n8n/app/values.yaml` lines 20-80 for reference.
>
> **initContainer omitted:** `fsGroup: 200` + `fsGroupChangePolicy: OnRootMismatch` on the pod's security context handles `/nexus-data` ownership on first mount. vaultwarden includes an extra chown initContainer for historical reasons; Nexus with fresh RBD PVC doesn't need it.

- [ ] **Step 5: Create kustomizeconfig.yaml** (name-reference for BOTH the HelmRelease valuesFrom AND the Job's script ConfigMap volume)

```yaml
# cluster/apps/nexus-system/nexus/app/kustomizeconfig.yaml
---
nameReference:
  - kind: ConfigMap
    version: v1
    fieldSpecs:
      - path: spec/valuesFrom/name
        kind: HelmRelease
      - path: spec/template/spec/volumes/configMap/name
        kind: Job
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

- [ ] **Step 8: Validate kustomize build + verify name hashing**

```bash
kubectl kustomize cluster/apps/nexus-system/nexus/app/ 2>&1 | tee /tmp/nexus-rendered.yaml
```

Some referenced resources don't exist yet (Job, RBAC, CNP, VPA, pod-monitor, provision.sh) — comment them out in the kustomization temporarily, re-render to confirm clean output. Add back as each later task creates them.

Verify the StatefulSet name lands as exactly `nexus`:

```bash
grep -E "kind: StatefulSet" -A 3 /tmp/nexus-rendered.yaml
```

Expected: `metadata.name: nexus`.

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

### Task 4: Provisioning Job + RBAC + script ConfigMap

**Files:**
- Create: `cluster/apps/nexus-system/nexus/app/provision-repos-rbac.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/provision-repos-job.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/provision.sh`

- [ ] **Step 1: RBAC (ServiceAccount only, no Role needed)**

```yaml
# cluster/apps/nexus-system/nexus/app/provision-repos-rbac.yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/core/serviceaccount_v1.json
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nexus-provisioner
  namespace: nexus-system
automountServiceAccountToken: false
```

Job consumes creds via `secretKeyRef` env (kubelet-injected) — no K8s API access.

- [ ] **Step 2: provision.sh**

GET-merge-PUT preserves existing privileges on the anonymous role.
Script runs on `alpine:3` and installs `curl` + `jq` at startup — avoids
depending on a prebuilt combined image.

```bash
#!/bin/sh
# cluster/apps/nexus-system/nexus/app/provision.sh
set -eu

command -v jq >/dev/null || apk add --no-cache jq curl

echo "Waiting for Nexus writable..."
for i in $(seq 1 60); do
  status=$(curl -sf -o /dev/null -w '%{http_code}' "${NEXUS_URL}/service/rest/v1/status/writable" || true)
  [ "${status}" = "200" ] && { echo "Nexus writable"; break; }
  echo "  attempt ${i}: HTTP ${status}, retrying in 10s..."
  sleep 10
done
[ "${status}" = "200" ] || { echo "Nexus never became writable"; exit 1; }

AUTH="-u ${NEXUS_USER}:${NEXUS_PASSWORD}"
API="${NEXUS_URL}/service/rest/v1"

upsert() {
  kind="$1" name="$2" body="$3"
  code=$(curl -sf -o /dev/null -w '%{http_code}' ${AUTH} "${API}/repositories/${name}" || echo 000)
  if [ "${code}" = "200" ]; then
    echo "  [${name}] exists, updating"
    curl -sf -X PUT -H "Content-Type: application/json" ${AUTH} -d "${body}" "${API}/repositories/${kind}/${name}"
  else
    echo "  [${name}] creating"
    curl -sf -X POST -H "Content-Type: application/json" ${AUTH} -d "${body}" "${API}/repositories/${kind}"
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

upsert apt/proxy apt-cli-github '{
  "name":"apt-cli-github","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":false},
  "proxy":{"remoteUrl":"https://cli.github.com/packages/","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "apt":{"distribution":"stable","flat":true}}'

upsert apt/proxy apt-nodesource '{
  "name":"apt-nodesource","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":false},
  "proxy":{"remoteUrl":"https://deb.nodesource.com/","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "apt":{"distribution":"stable","flat":true}}'

upsert apt/proxy apt-hashicorp '{
  "name":"apt-hashicorp","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":false},
  "proxy":{"remoteUrl":"https://apt.releases.hashicorp.com/","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "apt":{"distribution":"jammy","flat":false}}'

upsert apt/proxy apt-launchpad '{
  "name":"apt-launchpad","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":false},
  "proxy":{"remoteUrl":"https://ppa.launchpadcontent.net/","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true},
  "apt":{"distribution":"stable","flat":true}}'

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

# hosted cache — NOT a member of docker-group (workspace-private).
# Gets its own connector on 8083 so envbuilder can push/pull via
# /v2/<image> directly (clients expect OCI v2 at host root, not under
# /repository/<name>/).
upsert docker/hosted envbuilder-cache '{
  "name":"envbuilder-cache","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW"},
  "docker":{"v1Enabled":false,"forceBasicAuth":false,"httpPort":8083}}'

# docker-group with dedicated connector on 8082 (serves OCI v2 at host root)
upsert docker/group docker-group '{
  "name":"docker-group","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "group":{"memberNames":["docker-hub-proxy","ghcr-proxy","mcr-proxy"]},
  "docker":{"v1Enabled":false,"forceBasicAuth":false,"httpPort":8082}}'

# --- grant privileges to anonymous role (GET-merge-PUT to preserve defaults) ---
echo "Merging privileges into anonymous role..."
existing=$(curl -sf ${AUTH} "${API}/security/roles/anonymous")
merged=$(echo "${existing}" | jq -c '
  .privileges |= (. + [
    "nx-repository-view-*-*-read",
    "nx-repository-view-*-*-browse",
    "nx-metrics-all",
    "nx-healthcheck-read"
  ] | unique)
')
curl -sf -X PUT -H "Content-Type: application/json" ${AUTH} \
  -d "${merged}" "${API}/security/roles/anonymous"

# Ensure anonymous access is globally enabled
curl -sf -X PUT -H "Content-Type: application/json" ${AUTH} \
  -d '{"enabled":true,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}' \
  "${API}/security/anonymous"

# --- envbuilder-cache push: allow admin pushes (follow-up: dedicated user) ---
# No extra privilege work needed — admin role already has full write access.

echo "Provisioning complete."
```

> **Verify privilege ID during first run:** `nx-metrics-all` is the ID in recent Nexus 3 versions, but earlier versions split into `nx-metrics-read`. If the PUT 400s on unknown privilege, grep `/v1/security/privileges?type=application` for the current ID and adjust.

- [ ] **Step 3: Job manifest**

```yaml
# cluster/apps/nexus-system/nexus/app/provision-repos-job.yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/batch/job_v1.json
apiVersion: batch/v1
kind: Job
metadata:
  name: nexus-provision-repos
  namespace: nexus-system
  annotations:
    # Flux deletes+recreates on spec change (Job fields are immutable).
    # Value MUST be "Enabled" per Flux docs — "true" is ignored.
    kustomize.toolkit.fluxcd.io/force: "Enabled"
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
          # renovate: datasource=docker depName=alpine
          image: alpine:3.20.3@sha256:beefdbd8a1da6d2915566fde36db9db0b524443ee54b23de71fd5d9fe4f4b43d
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: [ALL]}
            readOnlyRootFilesystem: false  # apk needs /var/cache
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

The `name: nexus-provisioner-script` in the volume is rewritten by Kustomize to `nexus-provisioner-script-<hash>` via `kustomizeconfig.yaml` from Task 3 Step 5.

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/nexus-system/nexus/app/provision-repos-rbac.yaml \
        cluster/apps/nexus-system/nexus/app/provision-repos-job.yaml \
        cluster/apps/nexus-system/nexus/app/provision.sh
git commit -m "feat(nexus): provisioning Job creates 10 repos + anon privileges

Ref #968"
```

---

### Task 5: NetworkPolicy, VPA, VMPodScrape

**Files:**
- Create: `cluster/apps/nexus-system/nexus/app/network-policies.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/vpa.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/pod-monitor.yaml`

- [ ] **Step 1: CiliumNetworkPolicy** (tighter than namespace-wide, selects by pod label)

```yaml
# cluster/apps/nexus-system/nexus/app/network-policies.yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/cilium.io/ciliumnetworkpolicy_v2.json
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
    # Coder workspace envbuilder pods (labeled com.coder.resource: "true" by the template)
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: coder-system
            k8s:com.coder.resource: "true"
      toPorts:
        - ports:
            - {port: "8081", protocol: TCP}
            - {port: "8082", protocol: TCP}
            - {port: "8083", protocol: TCP}
    # Traefik pods (for external ingress)
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: traefik
            k8s:app.kubernetes.io/name: traefik
      toPorts:
        - ports:
            - {port: "8081", protocol: TCP}
            - {port: "8082", protocol: TCP}
            - {port: "8083", protocol: TCP}
    # vmagent metrics scrape
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            k8s:app.kubernetes.io/name: vmagent
      toPorts:
        - ports: [{port: "8081", protocol: TCP}]
    # Provisioning Job in-namespace
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

- [ ] **Step 2: VPA** (container name `main` per app-template's `controllers.main.containers.main`)

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

- [ ] **Step 3: VMPodScrape**

```yaml
# cluster/apps/nexus-system/nexus/app/pod-monitor.yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/operator.victoriametrics.com/vmpodscrape_v1beta1.json
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

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/nexus-system/nexus/app/network-policies.yaml \
        cluster/apps/nexus-system/nexus/app/vpa.yaml \
        cluster/apps/nexus-system/nexus/app/pod-monitor.yaml
git commit -m "feat(nexus): add CNP, VPA, and metrics scrape

Ref #968"
```

---

### Task 6: Traefik IngressRoute

**Files:**
- Create: `cluster/apps/traefik/traefik/ingress/nexus-system/kustomization.yaml`
- Create: `cluster/apps/traefik/traefik/ingress/nexus-system/certificates.yaml`
- Create: `cluster/apps/traefik/traefik/ingress/nexus-system/ingress-routes.yaml`

Pattern: mirror `cluster/apps/traefik/traefik/ingress/vaultwarden/`.

- [ ] **Step 1: Certificate**

```yaml
# cluster/apps/traefik/traefik/ingress/nexus-system/certificates.yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cert-manager.io/certificate_v1.json
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

- [ ] **Step 2: IngressRoute** (two routes, both TLS-terminated by Traefik, plain HTTP backend)

```yaml
# cluster/apps/traefik/traefik/ingress/nexus-system/ingress-routes.yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/traefik.io/ingressroute_v1alpha1.json
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
    - match: Host(`nexus-docker.lan.${EXTERNAL_DOMAIN}`)
      kind: Rule
      middlewares:
        - {name: lan-ip-whitelist, namespace: traefik}
      services:
        - name: nexus
          namespace: nexus-system
          passHostHeader: true
          port: 8082
  tls:
    secretName: "nexus-${EXTERNAL_DOMAIN/./-}-tls"
```

No path-prefix middleware — Nexus's `:8082` docker connector already serves `/v2/*` at host-root per OCI distribution spec.

- [ ] **Step 3: Kustomization**

```yaml
# cluster/apps/traefik/traefik/ingress/nexus-system/kustomization.yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./certificates.yaml
  - ./ingress-routes.yaml
```

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/traefik/traefik/ingress/nexus-system/
git commit -m "feat(nexus): add Traefik ingress + ZeroSSL cert

Ref #968"
```

---

### Task 7: README

**Files:**
- Create: `cluster/apps/nexus-system/nexus/README.md`

- [ ] **Step 1: Read template**

```bash
Read file_path="/workspaces/spruyt-labs/docs/templates/readme_template.md"
```

If missing, mirror `cluster/apps/qdrant-system/qdrant/README.md`.

- [ ] **Step 2: Write README**

Cover: Overview, Prerequisites (dependsOn: cert-manager, kyverno, rook-ceph-cluster-storage), Operation (UI login, provisioning Job rerun, PVC expansion), Troubleshooting (Job stuck, apt upstream down, metrics unreachable), References (spec link, #968, Sonatype docs).

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/nexus-system/nexus/README.md
git commit -m "docs(nexus): add README

Ref #968"
```

---

### Task 8: Validate + push PR 1

- [ ] **Step 1: Run qa-validator** (per `.claude/rules/02-validation.md`)

Dispatch the qa-validator agent. Fix BLOCKING findings. Per `feedback_run_megalinter_local.md`:

```bash
task dev-env:lint
```

- [ ] **Step 2: Push branch + open PR**

```bash
git push -u origin <branch>
gh pr create --repo anthony-spruyt/spruyt-labs \
  --title "feat(nexus): deploy Sonatype Nexus OSS (stack only)" \
  --body "$(cat <<'EOF'
## Summary
In-cluster Nexus 3 OSS as apt + docker proxy for Coder workspace builds. Stack-only — consumer wiring comes in next PR.

## Linked Issue
Ref #968

## Changes
- Namespace nexus-system (PSA restricted), app-template StatefulSet, 100Gi ceph-block PVC
- Multi-port Service: 8081 (UI/apt/REST) + 8082 (docker-group) + 8083 (envbuilder-cache)
- 10 repos provisioned via hashed Job; anonymous privileges merged into existing role
- Traefik ingress + ZeroSSL cert at nexus.lan.$DOMAIN and nexus-docker.lan.$DOMAIN
- CNP tight selectors (com.coder.resource, app.kubernetes.io/name), VPA rec-only, VMPodScrape
- No CoreDNS or Talos changes — plain HTTP inside cluster, TLS at Traefik only

## Testing
- [ ] qa-validator pass
- [ ] After merge: cluster-validator verdict
- [ ] UI login from dev PC
- [ ] apt smoke: curl https://nexus.lan.$DOMAIN/repository/apt-ubuntu-proxy/dists/jammy/Release
- [ ] docker smoke: docker pull nexus-docker.lan.$DOMAIN/alpine:3
EOF
)"
```

- [ ] **Step 3: User merges**

- [ ] **Step 4: Run cluster-validator**

Verify:
- StatefulSet `nexus` Ready (1/1); PVC bound at 100Gi
- Certificate `nexus` Ready in nexus-system
- Provisioning Job completed; 10 repos visible via `curl https://nexus.lan.<domain>/service/rest/v1/repositories`
- Anonymous metrics: `curl https://nexus.lan.<domain>/service/metrics/prometheus` returns metrics
- apt smoke: `curl https://nexus.lan.<domain>/repository/apt-ubuntu-proxy/dists/jammy/Release` returns 200
- docker smoke (group): `docker pull nexus-docker.lan.<domain>/alpine:3` succeeds
- docker cache connector reachable in-cluster (from a scratch debug pod in nexus-system):
  `curl -s http://nexus.nexus-system.svc.cluster.local:8083/v2/` returns 200 or the OCI unauthenticated challenge (not connection refused)

Triage failures per cluster-validator output.

---

## PR 2 — Coder integration

### Task 9: Update coder-workspace-env

**Files:**
- Modify: `cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml`

- [ ] **Step 1: Draft new docker config.json**

```json
{
  "auths": {
    "nexus.nexus-system.svc.cluster.local:8082": {
      "auth": "<base64 of admin:admin-password>"
    },
    "nexus.nexus-system.svc.cluster.local:8083": {
      "auth": "<base64 of admin:admin-password>"
    }
  }
}
```

Follow-up issue: replace admin with dedicated scoped user.

- [ ] **Step 2: User edits SOPS file**

```bash
sops cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml
```

Add/update keys:

```yaml
KANIKO_REGISTRY_MIRROR: "nexus.nexus-system.svc.cluster.local:8082"
ENVBUILDER_INSECURE: "true"
ENVBUILDER_DOCKER_CONFIG_BASE64: "<base64 of config.json above>"
```

> Note: `ENVBUILDER_CACHE_REPO` ends up on `:8083` (envbuilder-cache
> connector) — set via Terraform in Task 10, not here. The base64 config.json
> auth entry must cover the cache repo host:port: include entries for BOTH
> `nexus.nexus-system.svc.cluster.local:8082` (mirror pulls, optional since
> anonymous read) and `nexus.nexus-system.svc.cluster.local:8083` (cache
> pushes, required).

Leave existing upstream dockerhub/ghcr PAT env vars in place — Task 12 removes them.

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml
git commit -m "feat(coder): route envbuilder pulls through Nexus (svc DNS, plain HTTP)

Ref #968"
```

---

### Task 10: Update Coder devcontainer template

**Files:**
- Modify: `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf`

- [ ] **Step 1: Locate current ENVBUILDER_CACHE_REPO line**

```bash
Grep pattern="ENVBUILDER_CACHE_REPO" path="cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf" -n=true output_mode="content"
```

- [ ] **Step 2: Replace env map additions**

Edit around line 58:

```hcl
# Cache pushes hit the envbuilder-cache hosted repo on its own connector (8083).
# Pulls/mirror go through the docker-group connector (8082).
# URL has NO /repository/ segment — Nexus docker connectors serve OCI v2
# at host-root per the Distribution spec.
"ENVBUILDER_CACHE_REPO" : "nexus.nexus-system.svc.cluster.local:8083/envbuilder-cache/${data.coder_workspace.me.name}",
"KANIKO_REGISTRY_MIRROR" : "nexus.nexus-system.svc.cluster.local:8082",
"ENVBUILDER_INSECURE" : "true",
```

Remove the old ghcr path from ENVBUILDER_CACHE_REPO.

- [ ] **Step 3: Check for template Dockerfile**

```bash
Glob pattern="cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/**/Dockerfile"
```

- [ ] **Step 4: If Dockerfile exists, add apt proxy**

```dockerfile
RUN echo 'Acquire::http::Proxy "http://nexus.nexus-system.svc.cluster.local:8081/repository/apt-ubuntu-proxy/";' \
    > /etc/apt/apt.conf.d/01proxy
```

Plain HTTP; no `${external_domain}` substitution needed since we use the internal svc name.

For HTTPS-upstream apt features (nodesource, hashicorp, cli.github, launchpad), add a per-feature `sources.list.d/*.list` pointing at the corresponding passthrough proxy. Defer to per-need basis — document in template README.

If no Dockerfile exists in the template directory, document in the template README that consumer repos should add the apt proxy themselves. Not a blocker for this plan.

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf
git commit -m "feat(coder): point envbuilder cache + mirror at Nexus svc DNS

Ref #968"
```

---

### Task 11: Validate end-to-end Coder rebuild

- [ ] **Step 1: Push + merge PR 2**

```bash
gh pr create --repo anthony-spruyt/spruyt-labs \
  --title "feat(coder): route envbuilder through Nexus" \
  --body "$(cat <<'EOF'
## Summary
Point envbuilder at the in-cluster Nexus for image mirrors + kaniko layer cache.

## Linked Issue
Ref #968

## Changes
- coder-workspace-env.sops.yaml: add KANIKO_REGISTRY_MIRROR, ENVBUILDER_INSECURE, rewrite ENVBUILDER_DOCKER_CONFIG_BASE64 (svc DNS auth for :8082 + :8083)
- main.tf devcontainer template: update ENVBUILDER_CACHE_REPO to Nexus :8083, add mirror + insecure envs, bake apt proxy into base Dockerfile

## Testing
- [ ] 3+ workspace rebuilds succeed end-to-end
- [ ] envbuilder logs show Nexus endpoints for both pulls and cache push
EOF
)"
```

- [ ] **Step 2: cluster-validator**

- [ ] **Step 3: Rebuild one Coder workspace manually**

- [ ] **Step 4: Inspect envbuilder logs**

```bash
mcp__kubernetes__get_logs namespace=coder-system pod=<envbuilder-pod>
```

Expected:
- Kaniko log line referencing registry mirror `nexus.nexus-system.svc.cluster.local:8082`
- Base image pull resolved via Nexus path
- Layer cache push to `nexus.nexus-system.svc.cluster.local:8083/envbuilder-cache/<workspace>`

- [ ] **Step 5: Verify Nexus blob growth**

```bash
curl -u admin:<password> https://nexus.lan.<domain>/service/rest/v1/blobstores/default/quota-status
```

Blob count + size should increase.

- [ ] **Step 6: Rebuild 2 more workspaces**

Goal: 3+ successful rebuilds before PR 3 (per `feedback_no_observation_windows.md`).

---

## PR 3 — Cleanup

### Task 12: Remove upstream PATs

**Files:**
- Modify: `cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml`

- [ ] **Step 1: Confirm stability signal**

3+ workspace rebuilds succeeded. No build failures attributed to upstream rate-limits.

- [ ] **Step 2: User edits SOPS file**

```bash
sops cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml
```

Remove the dockerhub + ghcr PAT env vars now relocated to `nexus-upstream-creds` in Nexus.

- [ ] **Step 3: Commit + PR**

```bash
git add cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml
git commit -m "chore(coder): remove upstream PATs migrated to Nexus

Closes #968"

gh pr create --repo anthony-spruyt/spruyt-labs --title "chore(coder): remove legacy upstream PATs (Closes #968)"
```

- [ ] **Step 4: cluster-validator + one more rebuild**

- [ ] **Step 5: Close issue**

```bash
gh issue close 968 --repo anthony-spruyt/spruyt-labs \
  --comment "Completed via PRs <N>, <N+1>, <N+2>. Nexus deployed, Coder workspaces routed through it, legacy PATs removed."
```

---

## Runbook notes

1. **Admin password rotation.** `NEXUS_SECURITY_INITIAL_PASSWORD` applies only on first-boot with empty PVC. To rotate later: (a) `PUT /service/rest/v1/security/users/admin/change-password` via API, (b) update `nexus-admin` SOPS secret. Provisioning Job reads `admin-password` env; if stale it will 401 — rotate in the API first.

2. **Blob store full.** Online PVC expansion:
   `kubectl patch pvc data-nexus-0 -n nexus-system -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'`
   Ceph RBD resizes live.

3. **Docker connector ports.** Two connectors are opened inside Nexus:
   `docker-group` on `:8082` (serves proxy pulls for docker-hub/ghcr/mcr at
   host-root `/v2/`) and `envbuilder-cache` on `:8083` (serves hosted
   push/pull for the kaniko layer cache). Both exposed as Service ports.
   If Nexus logs show `BindException`, two repos claim the same port —
   check the provisioning JSON.

4. **Anonymous role clobbered.** Provisioning Job re-runs replace the anonymous role privileges with the merged list. If you manually add a privilege via UI, next Job run will preserve it only if the GET-merge-PUT reads it back first (which it does — that's the whole point). Don't disable anonymous-role management outside the Job.
