# Nexus OSS for Coder Workspace Builds — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Sonatype Nexus Repository OSS in-cluster as an apt + docker artifact proxy scoped to Coder workspace builds and developer workstations.

**Architecture:** Single-replica StatefulSet, 100Gi Ceph RBD PVC, Jetty native TLS with ZeroSSL cert, CoreDNS split-horizon (`nexus.${EXTERNAL_DOMAIN}` resolves to ClusterIP in-cluster, Traefik LB externally), REST API provisioning Job, scoped to Coder only (not Flux, not kubelet).

**Tech Stack:** Helm (sonatype/nexus-repository-manager official chart), Flux HelmRelease, cert-manager ZeroSSL, CoreDNS, Cilium CNP, Traefik IngressRoute, VictoriaMetrics VMPodScrape, VPA, SOPS for secrets.

**Reference:** `docs/superpowers/specs/2026-04-17-nexus-oss-coder-proxy-design.md`, issue [#968](https://github.com/anthony-spruyt/spruyt-labs/issues/968)

**Rollout:** 3 PRs. PR 1 = stack deployment (Tasks 1-10). PR 2 = Coder integration (Tasks 11-13). PR 3 = PAT cleanup (Task 14).

---

## Pre-flight checks

Before starting, verify the following in the repo:

- [ ] **Locate CoreDNS Corefile ConfigMap.** Likely at `cluster/apps/kube-system/coredns/` or managed by Talos. Run:

```bash
mcp__kubernetes__get_configmaps namespace=kube-system
```

Identify which ConfigMap holds the Corefile. If CoreDNS is Talos-managed (via `extraManifests`), the rewrite must be added to Talos config, not a Flux-managed ConfigMap. Record the location and whether it's Flux- or Talos-managed.

- [ ] **Locate existing HelmRepository for Sonatype.** Search:

```bash
Grep pattern="sonatype" path="cluster/flux/meta/repositories/helm"
```

If not present, a new `HelmRepository` must be added in Task 2.

- [ ] **Confirm ExternalDomain substitution key.** Already known: `${EXTERNAL_DOMAIN}` per `.claude/rules/patterns.md`.

- [ ] **Confirm ClusterIssuer name.** Already confirmed in spec: `zerossl-production`.

---

## PR 1 — Nexus stack deployment

### Task 1: Create namespace

**Files:**
- Create: `cluster/apps/nexus-system/namespace.yaml`
- Create: `cluster/apps/nexus-system/kustomization.yaml`
- Modify: `cluster/apps/kustomization.yaml` (register new namespace)

- [ ] **Step 1: Create namespace manifest**

```yaml
# cluster/apps/nexus-system/namespace.yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/core/namespace_v1.json
apiVersion: v1
kind: Namespace
metadata:
  name: nexus-system
  labels:
    kustomize.toolkit.fluxcd.io/prune: disabled
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

Read `cluster/apps/kustomization.yaml`. Insert `- ./nexus-system` alphabetically (between `nut-system` and `observability` or similar). Use Edit tool.

- [ ] **Step 4: Validate syntax**

```bash
kubectl kustomize cluster/apps/nexus-system/ --enable-helm 2>&1 | head -40
```

Expected: namespace manifest renders without error. `./nexus/ks.yaml` will error (not created yet) — expected at this stage.

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/nexus-system/namespace.yaml cluster/apps/nexus-system/kustomization.yaml cluster/apps/kustomization.yaml
git commit -m "feat(nexus): add nexus-system namespace

Ref #968"
```

---

### Task 2: Add Sonatype HelmRepository (if missing)

**Files:**
- Possibly create: `cluster/flux/meta/repositories/helm/sonatype.yaml`
- Possibly modify: `cluster/flux/meta/repositories/helm/kustomization.yaml`

- [ ] **Step 1: Check if already present**

```bash
Grep pattern="sonatype" path="cluster/flux/meta/repositories/helm"
```

If found, skip to Task 3.

- [ ] **Step 2: Create HelmRepository**

```yaml
# cluster/flux/meta/repositories/helm/sonatype.yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/source.toolkit.fluxcd.io/helmrepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: sonatype
  namespace: flux-system
spec:
  interval: 2h
  url: https://sonatype.github.io/helm3-charts/
```

- [ ] **Step 3: Register in kustomization**

Add `- ./sonatype.yaml` alphabetically to `cluster/flux/meta/repositories/helm/kustomization.yaml`.

- [ ] **Step 4: Verify chart available**

```bash
helm search repo sonatype/nexus-repository-manager --versions | head -10
```

(May require `helm repo add sonatype https://sonatype.github.io/helm3-charts/ && helm repo update` locally first.)

Record latest stable version for Task 4. Avoid `0.x` alphas.

- [ ] **Step 5: Commit**

```bash
git add cluster/flux/meta/repositories/helm/sonatype.yaml cluster/flux/meta/repositories/helm/kustomization.yaml
git commit -m "feat(flux): add sonatype helm repository

Ref #968"
```

---

### Task 3: Create SOPS secrets (admin password + upstream PATs)

**Files:**
- Create: `cluster/apps/nexus-system/nexus/app/nexus-admin.sops.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/nexus-upstream-creds.sops.yaml`

- [ ] **Step 1: Generate admin password template (unencrypted)**

Admin password must be at least 8 chars, include upper/lower/digit/special. Generate locally:

```bash
openssl rand -base64 24 | tr -d '/+=' | head -c 24
```

- [ ] **Step 2: Create SOPS-encrypted admin secret**

User runs manually (Claude does not decrypt/encrypt SOPS):

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
  admin-password: "<generated-password-from-step-1>"
```

- [ ] **Step 3: Create SOPS-encrypted upstream creds**

User runs:

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

**Source of values:** reuse the PATs already stored in `cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml` (decoded from `ENVBUILDER_DOCKER_CONFIG_BASE64`). User handles extraction manually.

- [ ] **Step 4: Verify encrypted**

```bash
head -20 cluster/apps/nexus-system/nexus/app/nexus-admin.sops.yaml
```

Expected: `sops:` block at bottom, `data:` fields are `ENC[AES256_GCM,...]` strings.

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/nexus-system/nexus/app/nexus-admin.sops.yaml cluster/apps/nexus-system/nexus/app/nexus-upstream-creds.sops.yaml
git commit -m "feat(nexus): add admin + upstream registry SOPS secrets

Ref #968"
```

---

### Task 4: Create cert-manager Certificate

**Files:**
- Create: `cluster/apps/nexus-system/nexus/app/certificate.yaml`

- [ ] **Step 1: Create Certificate manifest**

```yaml
# cluster/apps/nexus-system/nexus/app/certificate.yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/cert-manager.io/certificate_v1.json
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nexus-tls
  namespace: nexus-system
spec:
  secretName: nexus-tls
  issuerRef:
    name: zerossl-production
    kind: ClusterIssuer
  commonName: nexus.${EXTERNAL_DOMAIN}
  dnsNames:
    - nexus.${EXTERNAL_DOMAIN}
    - nexus-docker.${EXTERNAL_DOMAIN}
  keystores:
    pkcs12:
      create: true
      passwordSecretRef:
        name: nexus-keystore-password
        key: password
  privateKey:
    algorithm: RSA
    size: 2048
    rotationPolicy: Always
  usages:
    - server auth
    - digital signature
    - key encipherment
```

- [ ] **Step 2: Create keystore password SOPS secret**

Jetty needs a password for the PKCS12 keystore. User runs:

```bash
sops cluster/apps/nexus-system/nexus/app/nexus-keystore-password.sops.yaml
```

Content:

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: nexus-keystore-password
  namespace: nexus-system
type: Opaque
stringData:
  password: "<random-password>"
```

- [ ] **Step 3: Validate schema**

```bash
kubectl kustomize cluster/apps/nexus-system/ --enable-helm 2>&1 | head
```

(`./nexus/ks.yaml` still errors — expected.)

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/nexus-system/nexus/app/certificate.yaml cluster/apps/nexus-system/nexus/app/nexus-keystore-password.sops.yaml
git commit -m "feat(nexus): add TLS certificate via zerossl

Ref #968"
```

---

### Task 5: Create HelmRelease + values

**Files:**
- Create: `cluster/apps/nexus-system/nexus/app/release.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/values.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/kustomization.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/kustomizeconfig.yaml`

- [ ] **Step 1: Fetch chart values.yaml for exact key paths**

```bash
helm show values sonatype/nexus-repository-manager --version <version-from-task-2> > /tmp/nexus-chart-values.yaml
```

Review for: storage size key, image tag key, persistence, service ports, extraEnv, extraVolumes, extraVolumeMounts, securityContext. Record findings inline below.

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
  chart:
    spec:
      chart: nexus-repository-manager
      version: "<exact-version>"
      sourceRef:
        kind: HelmRepository
        name: sonatype
        namespace: flux-system
  interval: 4h
  valuesFrom:
    - kind: ConfigMap
      name: nexus-values
```

- [ ] **Step 3: Create values.yaml**

```yaml
# cluster/apps/nexus-system/nexus/app/values.yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/sonatype/nxrm-helm-repository/main/nexus-repository-manager/values.schema.json
---
statefulset:
  enabled: true

image:
  # Pin to the exact image tag matching chart appVersion
  # renovate: depName=sonatype/nexus3 datasource=docker
  tag: "<exact-tag>"

nexus:
  # Disable the random initial password generation; we inject our own
  # via the NEXUS_SECURITY_INITIAL_PASSWORD env var below
  properties:
    override: true
    data:
      # Jetty TLS configuration — enable native HTTPS on 8443
      application-port-ssl: "8443"
      # Enable docker registry on its own TLS port
      nexus.scripts.allowCreation: "false"
  env:
    - name: INSTALL4J_ADD_VM_PARAMS
      value: >-
        -Xms1200m -Xmx1200m
        -XX:MaxDirectMemorySize=2g
        -XX:+UnlockExperimentalVMOptions
        -XX:+UseCGroupMemoryLimitForHeap
        -Dkaraf.startLocalConsole=false
    - name: NEXUS_SECURITY_INITIAL_PASSWORD
      valueFrom:
        secretKeyRef:
          name: nexus-admin
          key: admin-password

persistence:
  enabled: true
  storageClass: ceph-block
  accessMode: ReadWriteOnce
  storageSize: 100Gi

service:
  type: ClusterIP
  # 8081 = HTTP for provisioning Job (internal, never exposed)
  # 8443 = HTTPS for UI/apt/REST
  # 5443 = HTTPS for docker registry
  port: 8081
  additionalPorts:
    - name: https
      port: 8443
      targetPort: 8443
    - name: docker-https
      port: 5443
      targetPort: 5443

# Extra volume mounts for Jetty TLS config + PKCS12 keystore
deployment:
  additionalVolumes:
    - name: nexus-tls
      secret:
        secretName: nexus-tls
        items:
          - key: keystore.p12
            path: keystore.p12
    - name: nexus-jetty-config
      configMap:
        name: nexus-jetty-config
  additionalVolumeMounts:
    - name: nexus-tls
      mountPath: /nexus-data/etc/ssl/keystore.p12
      subPath: keystore.p12
      readOnly: true
    - name: nexus-jetty-config
      mountPath: /nexus-data/etc/jetty/jetty-https.xml
      subPath: jetty-https.xml
      readOnly: true

resources:
  requests:
    cpu: 250m
    memory: 2Gi
  limits:
    memory: 4Gi

securityContext:
  runAsUser: 200
  runAsGroup: 200
  fsGroup: 200
  runAsNonRoot: true

podSecurityContext:
  seccompProfile:
    type: RuntimeDefault

ingress:
  enabled: false  # we use Traefik IngressRoute separately
```

> **Note:** Exact chart value keys MUST be verified from `/tmp/nexus-chart-values.yaml` in Step 1. The above uses common Sonatype chart conventions but may need adaptation. If any key doesn't exist in the chart, fall back to the chart's `extraEnvs` / `extraVolumes` / `extraContainer` equivalents or consider raw-manifests approach.

- [ ] **Step 4: Create kustomizeconfig.yaml**

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

- [ ] **Step 5: Create app kustomization**

```yaml
# cluster/apps/nexus-system/nexus/app/kustomization.yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./nexus-admin.sops.yaml
  - ./nexus-upstream-creds.sops.yaml
  - ./nexus-keystore-password.sops.yaml
  - ./certificate.yaml
  - ./release.yaml
  - ./jetty-config.yaml
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
configurations:
  - ./kustomizeconfig.yaml
```

- [ ] **Step 6: Create ks.yaml**

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
    - name: rook-ceph-cluster
  prune: true
  timeout: 10m
  wait: true
```

- [ ] **Step 7: Validate kustomize build**

```bash
kubectl kustomize cluster/apps/nexus-system/ --enable-helm 2>&1 | head -100
```

Expected: renders without schema errors. Some referenced files (jetty-config.yaml, provision-repos-*.yaml, network-policies.yaml, vpa.yaml, pod-monitor.yaml) don't exist yet — errors for those are expected at this stage. If blocking, comment them out in app/kustomization.yaml and add back as each task creates them.

- [ ] **Step 8: Commit**

```bash
git add cluster/apps/nexus-system/nexus/
git commit -m "feat(nexus): add HelmRelease + values

Ref #968"
```

---

### Task 6: Configure Jetty native TLS

**Files:**
- Create: `cluster/apps/nexus-system/nexus/app/jetty-config.yaml`

Nexus's embedded Jetty must be told to listen TLS on 8443 (HTTP UI/apt/REST) and 5443 (docker). Achieved via a custom `jetty-https.xml` referenced from `nexus.properties` + a keystore path.

- [ ] **Step 1: Create ConfigMap with Jetty HTTPS config**

```yaml
# cluster/apps/nexus-system/nexus/app/jetty-config.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nexus-jetty-config
  namespace: nexus-system
data:
  jetty-https.xml: |
    <?xml version="1.0"?>
    <!DOCTYPE Configure PUBLIC "-//Jetty//Configure//EN" "https://www.eclipse.org/jetty/configure_9_3.dtd">
    <Configure id="Server" class="org.eclipse.jetty.server.Server">
      <New id="sslContextFactory" class="org.eclipse.jetty.util.ssl.SslContextFactory$Server">
        <Set name="KeyStorePath">/nexus-data/etc/ssl/keystore.p12</Set>
        <Set name="KeyStoreType">PKCS12</Set>
        <Set name="KeyStorePassword">
          <SystemProperty name="nexus.ssl.keystore.password" default="changeit"/>
        </Set>
      </New>
      <Call name="addConnector">
        <Arg>
          <New class="org.eclipse.jetty.server.ServerConnector">
            <Arg name="server"><Ref refid="Server"/></Arg>
            <Arg name="factories">
              <Array type="org.eclipse.jetty.server.ConnectionFactory">
                <Item>
                  <New class="org.eclipse.jetty.server.SslConnectionFactory">
                    <Arg><Ref refid="sslContextFactory"/></Arg>
                    <Arg>http/1.1</Arg>
                  </New>
                </Item>
                <Item>
                  <New class="org.eclipse.jetty.server.HttpConnectionFactory">
                    <Arg>
                      <New class="org.eclipse.jetty.server.HttpConfiguration"/>
                    </Arg>
                  </New>
                </Item>
              </Array>
            </Arg>
            <Set name="host"><SystemProperty name="jetty.host"/></Set>
            <Set name="port">8443</Set>
          </New>
        </Arg>
      </Call>
    </Configure>
```

> **Note:** This is a reference structure for Jetty 9.x SSL configuration as used by Nexus 3. Exact content may need adjustment based on the chart's default `jetty.xml` handling. Verify against `/opt/sonatype/nexus/etc/jetty/jetty-https.xml` in a running Nexus pod if possible.

- [ ] **Step 2: Pass keystore password + enable SSL via env**

Verify `values.yaml` from Task 5 passes keystore password as Java system property. Update if needed:

```yaml
nexus:
  env:
    # ... existing env ...
    - name: INSTALL4J_ADD_VM_PARAMS
      value: >-
        -Xms1200m -Xmx1200m
        -XX:MaxDirectMemorySize=2g
        -Dkaraf.startLocalConsole=false
        -Dnexus.ssl.keystore.password=$(NEXUS_KEYSTORE_PASSWORD)
    - name: NEXUS_KEYSTORE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: nexus-keystore-password
          key: password
```

- [ ] **Step 3: Enable docker HTTPS connector in nexus.properties**

Docker registry gets its own port (5443). Configured inside Nexus UI when the docker repo is created (Task 8) — the repo declares its HTTP/HTTPS port. No additional Jetty config needed for this.

- [ ] **Step 4: Validate**

```bash
kubectl kustomize cluster/apps/nexus-system/ --enable-helm 2>&1 | grep -A 5 "jetty-https.xml"
```

Expected: ConfigMap with key `jetty-https.xml` renders.

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/nexus-system/nexus/app/jetty-config.yaml cluster/apps/nexus-system/nexus/app/values.yaml
git commit -m "feat(nexus): configure Jetty native TLS

Ref #968"
```

---

### Task 7: Create repository-provisioning Job + RBAC

**Files:**
- Create: `cluster/apps/nexus-system/nexus/app/provision-repos-rbac.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/provision-repos-job.yaml`

- [ ] **Step 1: Create ServiceAccount + Role**

```yaml
# cluster/apps/nexus-system/nexus/app/provision-repos-rbac.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nexus-provisioner
  namespace: nexus-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: nexus-provisioner
  namespace: nexus-system
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["nexus-admin", "nexus-upstream-creds"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: nexus-provisioner
  namespace: nexus-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: nexus-provisioner
subjects:
  - kind: ServiceAccount
    name: nexus-provisioner
    namespace: nexus-system
```

- [ ] **Step 2: Create provisioning Job**

The Job waits for Nexus writability, then POSTs REST calls to create 7 repositories. Idempotent via "create or update" logic.

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
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: provisioner
          image: curlimages/curl:8.10.1
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            readOnlyRootFilesystem: true
          env:
            - name: NEXUS_URL
              value: "http://nexus.nexus-system.svc.cluster.local:8081"
            - name: NEXUS_USER
              value: "admin"
            - name: NEXUS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: nexus-admin
                  key: admin-password
            - name: DOCKERHUB_USER
              valueFrom:
                secretKeyRef: {name: nexus-upstream-creds, key: dockerhub-username}
            - name: DOCKERHUB_TOKEN
              valueFrom:
                secretKeyRef: {name: nexus-upstream-creds, key: dockerhub-token}
            - name: GHCR_USER
              valueFrom:
                secretKeyRef: {name: nexus-upstream-creds, key: ghcr-username}
            - name: GHCR_TOKEN
              valueFrom:
                secretKeyRef: {name: nexus-upstream-creds, key: ghcr-token}
          command: ["/bin/sh", "-c"]
          args:
            - |
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
                # Check existence
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

              echo "Provisioning apt-ubuntu-proxy..."
              upsert apt/proxy apt-ubuntu-proxy '{
                "name": "apt-ubuntu-proxy",
                "online": true,
                "storage": {"blobStoreName": "default", "strictContentTypeValidation": true},
                "proxy": {"remoteUrl": "http://archive.ubuntu.com/ubuntu/", "contentMaxAge": 1440, "metadataMaxAge": 1440},
                "negativeCache": {"enabled": true, "timeToLive": 1440},
                "httpClient": {"blocked": false, "autoBlock": true},
                "apt": {"distribution": "jammy", "flat": false}
              }'

              echo "Provisioning apt-passthrough-proxy..."
              upsert apt/proxy apt-passthrough-proxy '{
                "name": "apt-passthrough-proxy",
                "online": true,
                "storage": {"blobStoreName": "default", "strictContentTypeValidation": true},
                "proxy": {"remoteUrl": "https://cli.github.com/packages/", "contentMaxAge": 1440, "metadataMaxAge": 1440},
                "negativeCache": {"enabled": true, "timeToLive": 1440},
                "httpClient": {"blocked": false, "autoBlock": true},
                "apt": {"distribution": "stable", "flat": true}
              }'

              echo "Provisioning docker-hub-proxy..."
              upsert docker/proxy docker-hub-proxy '{
                "name": "docker-hub-proxy",
                "online": true,
                "storage": {"blobStoreName": "default", "strictContentTypeValidation": true},
                "proxy": {"remoteUrl": "https://registry-1.docker.io", "contentMaxAge": 1440, "metadataMaxAge": 1440},
                "negativeCache": {"enabled": true, "timeToLive": 1440},
                "httpClient": {
                  "blocked": false, "autoBlock": true,
                  "authentication": {"type": "username", "username": "'"${DOCKERHUB_USER}"'", "password": "'"${DOCKERHUB_TOKEN}"'"}
                },
                "docker": {"v1Enabled": false, "forceBasicAuth": false, "httpsPort": 5443},
                "dockerProxy": {"indexType": "HUB", "cacheForeignLayers": false}
              }'

              echo "Provisioning ghcr-proxy..."
              upsert docker/proxy ghcr-proxy '{
                "name": "ghcr-proxy",
                "online": true,
                "storage": {"blobStoreName": "default", "strictContentTypeValidation": true},
                "proxy": {"remoteUrl": "https://ghcr.io", "contentMaxAge": 1440, "metadataMaxAge": 1440},
                "negativeCache": {"enabled": true, "timeToLive": 1440},
                "httpClient": {
                  "blocked": false, "autoBlock": true,
                  "authentication": {"type": "username", "username": "'"${GHCR_USER}"'", "password": "'"${GHCR_TOKEN}"'"}
                },
                "docker": {"v1Enabled": false, "forceBasicAuth": false},
                "dockerProxy": {"indexType": "REGISTRY", "cacheForeignLayers": false}
              }'

              echo "Provisioning mcr-proxy..."
              upsert docker/proxy mcr-proxy '{
                "name": "mcr-proxy",
                "online": true,
                "storage": {"blobStoreName": "default", "strictContentTypeValidation": true},
                "proxy": {"remoteUrl": "https://mcr.microsoft.com", "contentMaxAge": 1440, "metadataMaxAge": 1440},
                "negativeCache": {"enabled": true, "timeToLive": 1440},
                "httpClient": {"blocked": false, "autoBlock": true},
                "docker": {"v1Enabled": false, "forceBasicAuth": false},
                "dockerProxy": {"indexType": "REGISTRY", "cacheForeignLayers": false}
              }'

              echo "Provisioning envbuilder-cache..."
              upsert docker/hosted envbuilder-cache '{
                "name": "envbuilder-cache",
                "online": true,
                "storage": {"blobStoreName": "default", "strictContentTypeValidation": true, "writePolicy": "ALLOW"},
                "docker": {"v1Enabled": false, "forceBasicAuth": false}
              }'

              echo "Provisioning docker-group..."
              upsert docker/group docker-group '{
                "name": "docker-group",
                "online": true,
                "storage": {"blobStoreName": "default", "strictContentTypeValidation": true},
                "group": {"memberNames": ["docker-hub-proxy", "ghcr-proxy", "mcr-proxy", "envbuilder-cache"]},
                "docker": {"v1Enabled": false, "forceBasicAuth": false, "httpsPort": 5443}
              }'

              echo "All repositories provisioned successfully."
```

- [ ] **Step 3: Validate kustomize build**

```bash
kubectl kustomize cluster/apps/nexus-system/ --enable-helm 2>&1 | grep -E "kind: (Job|ServiceAccount|Role)"
```

Expected: 4 lines (Job, ServiceAccount, Role, RoleBinding).

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/nexus-system/nexus/app/provision-repos-rbac.yaml cluster/apps/nexus-system/nexus/app/provision-repos-job.yaml
git commit -m "feat(nexus): add REST-API repository provisioning Job

Ref #968"
```

---

### Task 8: Create NetworkPolicy, VPA, VMPodScrape

**Files:**
- Create: `cluster/apps/nexus-system/nexus/app/network-policies.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/vpa.yaml`
- Create: `cluster/apps/nexus-system/nexus/app/pod-monitor.yaml`

- [ ] **Step 1: Create CiliumNetworkPolicy**

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
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: coder-system
      toPorts:
        - ports:
            - {port: "8443", protocol: TCP}
            - {port: "5443", protocol: TCP}
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: traefik
      toPorts:
        - ports:
            - {port: "8443", protocol: TCP}
            - {port: "5443", protocol: TCP}
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
      toPorts:
        - ports:
            - {port: "8081", protocol: TCP}
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: nexus-system
            app.kubernetes.io/name: nexus-provisioner
      toPorts:
        - ports:
            - {port: "8081", protocol: TCP}
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

- [ ] **Step 2: Create VPA (recommendation-only)**

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
      - containerName: nexus-repository-manager
        minAllowed: {cpu: 1m, memory: 1Mi}
        maxAllowed: {memory: 4Gi}
```

> **Note:** Container name must match the Sonatype chart's container name. Verify via `kubectl get sts -n nexus-system nexus -o jsonpath='{.spec.template.spec.containers[*].name}'` after first rollout; adjust if different.

- [ ] **Step 3: Create VMPodScrape**

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
      basicAuth:
        username:
          name: nexus-admin
          key: admin-username
        password:
          name: nexus-admin
          key: admin-password
```

> **Note:** Metrics endpoint requires admin auth on Nexus 3. Add `admin-username: admin` to the `nexus-admin` SOPS secret if not already present.

- [ ] **Step 4: Validate**

```bash
kubectl kustomize cluster/apps/nexus-system/ --enable-helm 2>&1 | grep -E "kind:"
```

Expected kinds: Namespace, Secret (×3), Certificate, ConfigMap (×2), HelmRelease, ServiceAccount, Role, RoleBinding, Job, CiliumNetworkPolicy, VerticalPodAutoscaler, VMPodScrape.

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/nexus-system/nexus/app/network-policies.yaml cluster/apps/nexus-system/nexus/app/vpa.yaml cluster/apps/nexus-system/nexus/app/pod-monitor.yaml
git commit -m "feat(nexus): add CNP, VPA, and metrics scrape

Ref #968"
```

---

### Task 9: Add CoreDNS rewrite for split-horizon

**Files:**
- Modify: CoreDNS Corefile (exact location from pre-flight check)

> **Note:** This task depends on the pre-flight finding. If CoreDNS is Flux-managed, edit its values/ConfigMap. If Talos-managed (in `talos/talconfig.yaml` `extraManifests`), add rewrite there. The two options diverge significantly; the engineer must use the pre-flight finding to pick the correct path.

**Flux-managed path:**

- [ ] **Step 1: Locate CoreDNS values**

```bash
Glob pattern="cluster/apps/kube-system/coredns/**/*.yaml"
```

- [ ] **Step 2: Add rewrite plugin**

Edit the CoreDNS Corefile (typically in `values.yaml` under `servers:` or a dedicated `Corefile` key):

```text
rewrite name exact nexus.${EXTERNAL_DOMAIN} nexus.nexus-system.svc.cluster.local
rewrite name exact nexus-docker.${EXTERNAL_DOMAIN} nexus.nexus-system.svc.cluster.local
```

Insert before the `kubernetes` plugin directive.

**Talos-managed path:**

- [ ] **Step 1 (alt): Edit Talos extraManifests**

Find Talos CoreDNS ConfigMap override. Add same rewrite lines. Regenerate and apply Talos configs per `.claude/memory/feedback_talos_genconfig.md`.

- [ ] **Step 3: Validate**

```bash
mcp__kubernetes__exec_in_pod namespace=kube-system pod=<coredns-pod> command=["sh","-c","cat /etc/coredns/Corefile"]
```

Expected: rewrite lines present.

- [ ] **Step 4: Commit**

```bash
git add <file-modified>
git commit -m "feat(coredns): add rewrite for nexus FQDNs

Ref #968"
```

---

### Task 10: Add Traefik IngressRoute (external access)

**Files:**
- Create: `cluster/apps/traefik/traefik/ingress/nexus-system/kustomization.yaml`
- Create: `cluster/apps/traefik/traefik/ingress/nexus-system/certificates.yaml`
- Create: `cluster/apps/traefik/traefik/ingress/nexus-system/ingress-routes.yaml`
- Modify: `cluster/apps/nexus-system/nexus/ks.yaml` (add second Kustomization for ingress)

> **Note:** Existing Traefik ingress patterns split cert creation under the Traefik namespace (Traefik-scoped TLSStore) or reference the cert from the app namespace. Examine `cluster/apps/traefik/traefik/ingress/vaultwarden/` for the exact pattern used here and mirror it.

- [ ] **Step 1: Study existing pattern**

```bash
Read file_path="/workspaces/spruyt-labs/cluster/apps/traefik/traefik/ingress/vaultwarden/ingress-routes.yaml"
Read file_path="/workspaces/spruyt-labs/cluster/apps/traefik/traefik/ingress/vaultwarden/certificates.yaml"
Read file_path="/workspaces/spruyt-labs/cluster/apps/traefik/traefik/ingress/vaultwarden/kustomization.yaml"
```

- [ ] **Step 2: Create certificates.yaml mirroring pattern**

For TLS passthrough (recommended, since Nexus already serves TLS), the ingress route uses `IngressRouteTCP` with SNI. Alternative: re-encrypt via `IngressRoute` + `serversTransport` trusting the ZeroSSL cert.

Go with **passthrough** for simplicity:

```yaml
# cluster/apps/traefik/traefik/ingress/nexus-system/certificates.yaml
---
# No cert needed — passthrough mode; Nexus serves its own TLS from nexus-tls secret in nexus-system namespace
# Empty file kept for pattern consistency; can be removed from kustomization if unused.
```

- [ ] **Step 3: Create ingress-routes.yaml**

```yaml
# cluster/apps/traefik/traefik/ingress/nexus-system/ingress-routes.yaml
---
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: nexus-ui
  namespace: nexus-system
spec:
  entryPoints: [websecure]
  routes:
    - match: HostSNI(`nexus.${EXTERNAL_DOMAIN}`)
      services:
        - name: nexus
          port: 8443
  tls:
    passthrough: true
---
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: nexus-docker
  namespace: nexus-system
spec:
  entryPoints: [websecure]
  routes:
    - match: HostSNI(`nexus-docker.${EXTERNAL_DOMAIN}`)
      services:
        - name: nexus
          port: 5443
  tls:
    passthrough: true
```

- [ ] **Step 4: Create kustomization.yaml**

```yaml
# cluster/apps/traefik/traefik/ingress/nexus-system/kustomization.yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./ingress-routes.yaml
```

- [ ] **Step 5: Add ingress Kustomization to nexus ks.yaml**

Append to `cluster/apps/nexus-system/nexus/ks.yaml`:

```yaml
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
  postBuild:
    substitute: {}
    substituteFrom:
      - kind: ConfigMap
        name: cluster-settings
      - kind: Secret
        name: cluster-settings
```

(Verify `postBuild.substituteFrom` matches existing ingress Kustomizations in repo — pattern may differ.)

- [ ] **Step 6: Validate**

```bash
kubectl kustomize cluster/apps/traefik/traefik/ingress/nexus-system/ 2>&1 | head -40
```

Expected: two IngressRouteTCP renders.

- [ ] **Step 7: Commit + push for PR 1 milestone**

```bash
git add cluster/apps/traefik/traefik/ingress/nexus-system/ cluster/apps/nexus-system/nexus/ks.yaml
git commit -m "feat(nexus): add Traefik TLS-passthrough ingress

Ref #968"
```

- [ ] **Step 8: Run qa-validator (MANDATORY before PR)**

Dispatch qa-validator per `.claude/rules/02-validation.md`.

- [ ] **Step 9: Push PR 1**

Create PR with title `feat(nexus): deploy Sonatype Nexus OSS (stack only, no consumers)`. Body references #968. User pushes / merges.

- [ ] **Step 10: Run cluster-validator after push**

Dispatch cluster-validator. Verify:
- `nexus-system` namespace exists
- StatefulSet `nexus` is Ready
- PVC bound
- Certificate `nexus-tls` is Ready
- Provisioning Job completed (check `kubectl get jobs -n nexus-system`)
- UI reachable from dev PC: `curl -v https://nexus.${EXTERNAL_DOMAIN}` returns 200
- Smoke test apt: `curl -v https://nexus.${EXTERNAL_DOMAIN}/repository/apt-ubuntu-proxy/dists/jammy/Release` returns 200
- Smoke test docker: `docker pull nexus-docker.${EXTERNAL_DOMAIN}/library/alpine:3` succeeds

If any fails, fix forward or rollback per cluster-validator verdict.

---

## PR 2 — Coder integration

### Task 11: Rewrite ENVBUILDER_DOCKER_CONFIG_BASE64

**Files:**
- Modify: `cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml`

- [ ] **Step 1: Draft new docker config (unencrypted)**

```json
{
  "auths": {
    "nexus-docker.${EXTERNAL_DOMAIN}": {}
  },
  "registry-mirrors": [
    "https://nexus-docker.${EXTERNAL_DOMAIN}"
  ]
}
```

Note: `registry-mirrors` in docker daemon config is docker.io-specific. For envbuilder/kaniko multi-registry mirroring, instead remap upstreams via kaniko flags. Actual config should be kaniko's `--registry-mirror` or rewrite via `--registry-map` — verify envbuilder docs.

**Envbuilder-native config:** envbuilder supports registry remapping via env `ENVBUILDER_IGNORE_PATHS`, `ENVBUILDER_BUILD_CONTEXT_PATH`, and kaniko passthrough. The simplest approach: set `ENVBUILDER_DOCKER_CONFIG_BASE64` to a standard dockerconfigjson with auth entries AND configure kaniko registry mirrors via kaniko flags.

- [ ] **Step 2: Update sops file**

User runs:

```bash
sops cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml
```

Update `ENVBUILDER_DOCKER_CONFIG_BASE64` to:

```yaml
ENVBUILDER_DOCKER_CONFIG_BASE64: "<base64 of the new dockerconfigjson above>"
```

Leave old upstream PATs in file for now — remove in Task 14 after stability confirmed.

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml
git commit -m "feat(coder): point envbuilder docker config at Nexus

Ref #968"
```

---

### Task 12: Update envbuilder cache repo + apt proxy in template

**Files:**
- Modify: `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf`

- [ ] **Step 1: Locate current cache repo line**

```bash
Grep pattern="ENVBUILDER_CACHE_REPO" path="cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf" -n=true output_mode="content"
```

Record line number.

- [ ] **Step 2: Replace with Nexus endpoint**

```hcl
# main.tf, around line 58
"ENVBUILDER_CACHE_REPO" : "nexus-docker.${var.external_domain}/envbuilder-cache/${data.coder_workspace.me.name}",
```

Ensure `var.external_domain` is declared. If not, add:

```hcl
variable "external_domain" {
  type        = string
  description = "Cluster external domain, sourced from Coder template parameters or module config"
}
```

Check how existing templates resolve `${EXTERNAL_DOMAIN}` — likely already wired via Coder's template param injection.

- [ ] **Step 3: Add kaniko mirror flags**

```hcl
# In the envbuilder env map, add:
"ENVBUILDER_DOCKER_CONFIG_BASE64" : data.coder_parameter.docker_config.value,
"KANIKO_ARGS" : "--registry-mirror=nexus-docker.${var.external_domain}",
```

Verify envbuilder version supports `KANIKO_ARGS` env passthrough; otherwise bake equivalent into a custom envbuilder wrapper or set directly via envbuilder-supported vars.

- [ ] **Step 4: Update devcontainer template Dockerfile (baked apt proxy)**

Find the devcontainer Dockerfile template in `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/`. If absent, the template may not bake a Dockerfile — envbuilder uses the repo's own `.devcontainer/Dockerfile`. In that case, defer apt proxy injection to a later, per-repo change (not this plan) and rely on docker pull-through only for PR 2.

If the template does include a base Dockerfile:

```dockerfile
RUN echo 'Acquire::https::Proxy "https://nexus.${external_domain}/repository/apt-ubuntu-proxy/";' \
    > /etc/apt/apt.conf.d/01proxy
```

Where `${external_domain}` is substituted by Terraform at template render.

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf
git commit -m "feat(coder): move envbuilder cache + apt proxy to Nexus

Ref #968"
```

---

### Task 13: Validate end-to-end Coder workspace rebuild

- [ ] **Step 1: Push PR 2**

Create PR `feat(coder): route envbuilder through Nexus`. User merges.

- [ ] **Step 2: Run cluster-validator**

- [ ] **Step 3: Trigger a test workspace rebuild**

Manually recreate one Coder workspace. Monitor envbuilder logs:

```bash
mcp__kubernetes__get_logs namespace=coder-system pod=<envbuilder-pod>
```

Expected evidence of Nexus use:
- apt output shows `https://nexus.${EXTERNAL_DOMAIN}/...` URLs
- docker pulls show `nexus-docker.${EXTERNAL_DOMAIN}/...` image refs
- Kaniko logs show layer push to `nexus-docker.${EXTERNAL_DOMAIN}/envbuilder-cache/...`

- [ ] **Step 4: Verify Nexus blob store growth**

```bash
curl -u admin:<password> https://nexus.${EXTERNAL_DOMAIN}/service/rest/v1/blobstores/default/quota-status
```

Blob count should increase; size should grow.

- [ ] **Step 5: If issues, document + rollback or roll-forward**

---

## PR 3 — Cleanup

### Task 14: Remove upstream PATs from coder-workspace-env

Wait ~1 week after PR 2 to confirm stability.

**Files:**
- Modify: `cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml`

- [ ] **Step 1: Verify Nexus has been serving consistently**

Check VM metrics for Nexus uptime over past 7 days. Check Coder workspace build success rate (no upstream rate-limit errors).

- [ ] **Step 2: Edit SOPS file**

User runs:

```bash
sops cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml
```

Remove all upstream PAT env vars now migrated to `nexus-upstream-creds`.

- [ ] **Step 3: Commit + push**

```bash
git add cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml
git commit -m "chore(coder): remove upstream PATs migrated to Nexus

Ref #968"
```

- [ ] **Step 4: Cluster-validator + one more workspace rebuild to confirm nothing regressed**

- [ ] **Step 5: Close issue #968**

```bash
gh issue close 968 --repo anthony-spruyt/spruyt-labs --comment "Completed via PRs <N>, <N+1>, <N+2>. Nexus deployed, Coder workspaces routed through it, legacy PATs removed."
```

---

## Open items to resolve during execution

The following require in-flight investigation and decision; they are **not blockers** for starting Task 1 but must be closed before the corresponding task:

1. **CoreDNS management model** (blocks Task 9) — Flux-managed or Talos-managed.
2. **Exact Sonatype chart value key paths** (blocks Task 5 Step 2) — verified via `helm show values`.
3. **Jetty TLS wiring specifics** (blocks Task 6) — exact env var / ConfigMap mount path Nexus expects for custom `jetty-https.xml`. May require inspecting a live Nexus pod filesystem or consulting Nexus docs via Context7.
4. **Metrics auth** (blocks Task 8 Step 3) — confirm whether Nexus 3 Prometheus metrics endpoint needs admin auth or can be anonymous.
5. **Kaniko registry mirror mechanism** (blocks Task 12 Step 3) — exact envbuilder passthrough variable for kaniko mirror flags.
6. **Traefik TLS-passthrough pattern** (blocks Task 10) — whether repo uses `IngressRouteTCP` elsewhere; if not, fall back to terminate-and-reencrypt with `serversTransport`.

Resolve each by reading chart values, upstream docs, or existing similar resources in the repo before writing the final manifest.
