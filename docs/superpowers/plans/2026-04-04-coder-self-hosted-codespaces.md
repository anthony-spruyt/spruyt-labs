# Coder Self-Hosted Codespaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Coder on the homelab Kubernetes cluster to provide browser-based VS Code development environments built from any repo's `devcontainer.json`, accessible externally via Authentik OIDC.

**Architecture:** Coder control plane deployed as a HelmRelease in `coder-system` namespace with CNPG PostgreSQL, Authentik OIDC integration, Traefik ingress at `code.${EXTERNAL_DOMAIN}`, and a Terraform template that creates workspace pods with DinD, cluster-admin SA, and secrets mounted from the cluster.

**Tech Stack:** Coder, FluxCD, CNPG PostgreSQL, Authentik (OIDC), Traefik, Rook Ceph, CiliumNetworkPolicy, ExternalSecrets, SOPS/Age

**Spec:** `docs/superpowers/specs/2026-04-04-coder-self-hosted-codespaces-design.md`

**GitHub Issue:** Create before starting work (see Task 1).

---

## File Structure

### New files in `cluster/apps/coder-system/`

```text
cluster/apps/coder-system/
├── namespace.yaml
├── kustomization.yaml
└── coder/
    ├── ks.yaml
    └── app/
        ├── kustomization.yaml
        ├── release.yaml                          # HelmRelease for Coder
        ├── values.yaml                           # Helm values (OIDC, DB, URL config)
        ├── kustomizeconfig.yaml                  # nameReference for configMapGenerator
        ├── coder-cnpg-cluster.yaml               # CNPG PostgreSQL cluster
        ├── coder-cnpg-object-stores.yaml         # Barman S3 backup config
        ├── coder-cnpg-scheduled-backups.yaml      # Daily backup schedule
        ├── coder-secrets.sops.yaml               # SOPS: AWS creds, env tokens, talosconfig, terraform creds
        ├── coder-ssh-signing-key.sops.yaml       # SOPS: dedicated SSH signing key (separate from Flux-managed secrets)
        ├── authentik-secret-store.yaml           # SecretStore for reading from authentik-system
        ├── coder-oauth-external-secret.yaml      # ExternalSecret for OIDC creds
        ├── github-secret-store.yaml              # SecretStore for reading from github-system
        ├── github-external-secret.yaml           # ExternalSecret for GitHub token
        ├── oauth-rotation-rbac.yaml              # Role/RoleBinding for oauth-secret-rotation
        ├── workspace-rbac.yaml                   # ServiceAccount + cluster-admin ClusterRoleBinding
        ├── ssh-key-rotation/
        │   ├── kustomization.yaml
        │   ├── cronjob.yaml
        │   ├── service-account.yaml
        │   ├── role.yaml
        │   ├── role-binding.yaml
        │   └── coder-ssh-rotation-token.sops.yaml
        ├── network-policies.yaml
        └── vpa.yaml
```

### New files in `cluster/apps/traefik/traefik/ingress/coder-system/`

```text
cluster/apps/traefik/traefik/ingress/coder-system/
├── kustomization.yaml
├── ingress-routes.yaml
└── certificates.yaml
```

### New files in `cluster/apps/authentik-system/authentik/app/blueprints/`

```text
cluster/apps/authentik-system/authentik/app/blueprints/coder-sso.yaml
```

### Modified files

```text
cluster/apps/kustomization.yaml                                    # Add ./coder-system
cluster/apps/traefik/traefik/ks.yaml                               # Add coder to dependsOn
cluster/apps/traefik/traefik/ingress/kustomization.yaml            # Add ./coder-system
cluster/apps/authentik-system/authentik/app/kustomization.yaml     # Add blueprint to ConfigMap
cluster/apps/authentik-system/authentik/app/external-secrets-rbac.yaml  # Add coder-oauth-reader
cluster/apps/github-system/github-token-rotation/app/cronjob.yaml  # Add coder-system to force_sync
cluster/apps/github-system/github-token-rotation/app/kustomization.yaml  # Add reader-role-binding
cluster/apps/github-system/github-token-rotation/app/reader-role-binding-coder-system.yaml  # New
cluster/apps/kube-system/descheduler/app/values.yaml               # Add coder-system exclusion
cluster/flux/meta/repositories/helm/coder-charts.yaml              # New HelmRepository
cluster/flux/meta/repositories/helm/kustomization.yaml             # Add coder-charts
```

### New files in `coder/templates/devcontainer/`

```text
coder/templates/devcontainer/
├── main.tf
└── README.md
```

---

## Task 1: Create GitHub Issue

**Files:** None (CLI only)

- [ ] **Step 1: Search for existing issue**

```bash
gh issue list --repo anthony-spruyt/spruyt-labs --search "coder" --state open
```

Expected: No existing Coder issues.

- [ ] **Step 2: Read the feature request template**

Read `.github/ISSUE_TEMPLATE/feature_request.yml` to get the required fields.

- [ ] **Step 3: Create the issue**

```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "feat(coder): deploy self-hosted Coder for browser-based development" \
  --label "enhancement" \
  --body "$(cat <<'EOF'
## Summary
Deploy Coder (self-hosted Codespaces) on the homelab cluster to provide browser-based VS Code development environments, accessible from any device via Authentik OIDC.

## Motivation
Enable development from a phone or any browser while away from the desktop. Supports any repo's devcontainer.json with full toolchain access (kubectl, helm, flux, talosctl, Claude CLI, Docker).

## Acceptance Criteria
- [ ] Coder control plane deployed via HelmRelease in coder-system namespace
- [ ] CNPG PostgreSQL with Barman S3 backups
- [ ] Authentik OIDC integration (login via SSO)
- [ ] Traefik IngressRoute at code.${EXTERNAL_DOMAIN}
- [ ] Workspace pods built from devcontainer.json with DinD support
- [ ] GitHub App token integration via existing github-system infrastructure
- [ ] SSH signing key rotation CronJob
- [ ] CiliumNetworkPolicy for all components
- [ ] VPA (recommendation-only)

## Affected Area
Apps (cluster/apps/)
EOF
)"
```

- [ ] **Step 4: Note the issue number**

Record the issue number (e.g., `#NNN`) for use in all commits below.

---

## Task 2: Add Coder Helm Repository

**Files:**
- Create: `cluster/flux/meta/repositories/helm/coder-charts.yaml`
- Modify: `cluster/flux/meta/repositories/helm/kustomization.yaml`

- [ ] **Step 1: Research the Coder Helm chart registry URL**

Use Context7 `resolve-library-id` for "coder helm chart", then `query-docs`. If not available, check GitHub:

```bash
gh search code "helm.coder.com" --repo coder/coder --language yaml
```

Or fetch the chart repo README via WebFetch from `https://raw.githubusercontent.com/coder/coder/main/helm/README.md`.

The Helm repo URL is `https://helm.coder.com/v2`.

- [ ] **Step 2: Create HelmRepository**

Create `cluster/flux/meta/repositories/helm/coder-charts.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas-cjso.pages.dev/source.toolkit.fluxcd.io/helmrepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: coder-charts
  namespace: flux-system
spec:
  interval: 4h
  url: https://helm.coder.com/v2
```

- [ ] **Step 3: Add to kustomization**

Add `- ./coder-charts.yaml` to `cluster/flux/meta/repositories/helm/kustomization.yaml` resources list.

- [ ] **Step 4: Commit**

```bash
git add cluster/flux/meta/repositories/helm/coder-charts.yaml cluster/flux/meta/repositories/helm/kustomization.yaml
git commit -m "feat(coder): add Coder Helm repository

Ref #NNN"
```

---

## Task 3: Create Namespace and Flux Scaffolding

**Files:**
- Create: `cluster/apps/coder-system/namespace.yaml`
- Create: `cluster/apps/coder-system/kustomization.yaml`
- Create: `cluster/apps/coder-system/coder/ks.yaml`
- Modify: `cluster/apps/kustomization.yaml`

- [ ] **Step 1: Create namespace**

Create `cluster/apps/coder-system/namespace.yaml`:

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: coder-system
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
    descheduler.kubernetes.io/exclude: "true"
```

- [ ] **Step 2: Create namespace kustomization**

Create `cluster/apps/coder-system/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./coder/ks.yaml
```

- [ ] **Step 3: Create Flux Kustomization**

Create `cluster/apps/coder-system/coder/ks.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas-cjso.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app coder
  namespace: flux-system
spec:
  targetNamespace: coder-system
  path: ./cluster/apps/coder-system/coder/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: cnpg-operator
    - name: plugin-barman-cloud
    - name: external-secrets
    - name: authentik
  prune: true
  timeout: 5m
  wait: true
```

- [ ] **Step 4: Register in top-level kustomization**

Add `- ./coder-system` to `cluster/apps/kustomization.yaml` resources list (alphabetical order).

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/coder-system/namespace.yaml cluster/apps/coder-system/kustomization.yaml cluster/apps/coder-system/coder/ks.yaml cluster/apps/kustomization.yaml
git commit -m "feat(coder): add namespace and Flux scaffolding

Ref #NNN"
```

---

## Task 4: CNPG PostgreSQL Cluster

**Files:**
- Create: `cluster/apps/coder-system/coder/app/coder-cnpg-cluster.yaml`
- Create: `cluster/apps/coder-system/coder/app/coder-cnpg-object-stores.yaml`
- Create: `cluster/apps/coder-system/coder/app/coder-cnpg-scheduled-backups.yaml`

- [ ] **Step 1: Create CNPG Cluster**

Create `cluster/apps/coder-system/coder/app/coder-cnpg-cluster.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/postgresql.cnpg.io/cluster_v1.json
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: coder-cnpg-cluster
spec:
  affinity:
    enablePodAntiAffinity: true
    podAntiAffinityType: required
    topologyKey: kubernetes.io/hostname
  bootstrap:
    initdb:
      database: coder
      owner: coder
  enableSuperuserAccess: true
  imageName: "ghcr.io/cloudnative-pg/postgresql:18@sha256:664ebfe87d1cda6f429613d265ae1db758eb19ee050a2752ac38e856b0bd24ad"
  instances: 2
  monitoring:
    enablePodMonitor: true
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      enabled: true
      isWALArchiver: true
      parameters:
        barmanObjectName: coder-cnpg-aws-object-store
  postgresql:
    parameters:
      shared_buffers: 128MB
  primaryUpdateMethod: switchover
  primaryUpdateStrategy: unsupervised
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 100m
      memory: 512Mi
  storage:
    pvcTemplate:
      storageClassName: rbd-fast-delete
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 2Gi
```

- [ ] **Step 2: Create S3 Object Store**

Create `cluster/apps/coder-system/coder/app/coder-cnpg-object-stores.yaml`:

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/barmancloud.cnpg.io/objectstore_v1.json
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: coder-cnpg-aws-object-store
spec:
  retentionPolicy: 7d
  configuration:
    destinationPath: s3://spruyt-labs-470715245270-prod-cnpg-backup/object-store
    s3Credentials:
      accessKeyId:
        name: coder-secrets
        key: AWS_ACCESS_KEY_ID
      secretAccessKey:
        name: coder-secrets
        key: AWS_SECRET_ACCESS_KEY
    data:
      compression: bzip2
    wal:
      compression: bzip2
      maxParallel: 8
```

- [ ] **Step 3: Create Scheduled Backup**

Create `cluster/apps/coder-system/coder/app/coder-cnpg-scheduled-backups.yaml`:

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/postgresql.cnpg.io/scheduledbackup_v1.json
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: coder-cnpg-daily-scheduled-backup
spec:
  immediate: true
  suspend: false
  schedule: "0 15 * * *"
  cluster:
    name: coder-cnpg-cluster
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
  backupOwnerReference: self
```

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/coder-system/coder/app/coder-cnpg-cluster.yaml cluster/apps/coder-system/coder/app/coder-cnpg-object-stores.yaml cluster/apps/coder-system/coder/app/coder-cnpg-scheduled-backups.yaml
git commit -m "feat(coder): add CNPG PostgreSQL cluster with Barman S3 backups

Ref #NNN"
```

---

## Task 5: SOPS Secrets (User Creates)

**Files:**
- Create: `cluster/apps/coder-system/coder/app/coder-secrets.sops.yaml` (user creates manually)
- Create: `cluster/apps/coder-system/coder/app/coder-ssh-signing-key.sops.yaml` (user creates manually)
- Create: `cluster/apps/authentik-system/authentik/app/authentik-coder-oauth.sops.yaml` (user creates manually)
- Create: `cluster/apps/coder-system/coder/app/ssh-key-rotation/coder-ssh-rotation-token.sops.yaml` (user creates manually)

This task requires the user to create SOPS-encrypted secrets. Provide templates.

**Important:** The SSH signing key is in a **separate** Secret (`coder-ssh-signing-key`) from
the main `coder-secrets`. This is because the SSH key rotation CronJob (Task 9) needs to patch
the Secret, but Flux-managed SOPS Secrets get overwritten on reconciliation. The
`coder-ssh-signing-key` Secret is created initially by SOPS but then managed by the CronJob.
Use `spec.patches` in the Flux Kustomization or annotate with
`kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` so Flux only creates it once.

- [ ] **Step 1: Provide coder-secrets template**

The user creates `cluster/apps/coder-system/coder/app/coder-secrets.sops.yaml` containing:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: coder-secrets
  namespace: coder-system
stringData:
  # AWS credentials for CNPG Barman backups
  AWS_ACCESS_KEY_ID: "<value>"
  AWS_SECRET_ACCESS_KEY: "<value>"
  # Talos client config
  talosconfig: "<value>"
  # Terraform credentials
  terraform-credentials: "<value>"
  # Claude API key
  ANTHROPIC_API_KEY: "<value>"
```

Encrypt with: `sops -e -i cluster/apps/coder-system/coder/app/coder-secrets.sops.yaml`

- [ ] **Step 1b: Provide SSH signing key template**

The user creates `cluster/apps/coder-system/coder/app/coder-ssh-signing-key.sops.yaml` containing:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: coder-ssh-signing-key
  namespace: coder-system
  annotations:
    kustomize.toolkit.fluxcd.io/ssa: IfNotPresent
stringData:
  id_ed25519: "<initial-ssh-private-key>"
  id_ed25519.pub: "<initial-ssh-public-key>"
```

The `IfNotPresent` annotation ensures Flux creates this Secret once, then the SSH key rotation CronJob manages it going forward.

Encrypt with: `sops -e -i cluster/apps/coder-system/coder/app/coder-ssh-signing-key.sops.yaml`

- [ ] **Step 2: Provide OIDC secret template**

The user creates `cluster/apps/authentik-system/authentik/app/authentik-coder-oauth.sops.yaml` containing:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: authentik-coder-oauth
  namespace: authentik-system
stringData:
  CODER_OIDC_CLIENT_ID: "<generated-uuid>"
  CODER_OIDC_CLIENT_SECRET: "<generated-secret>"
```

Encrypt with: `sops -e -i cluster/apps/authentik-system/authentik/app/authentik-coder-oauth.sops.yaml`

- [ ] **Step 3: Provide SSH rotation token template**

The user creates `cluster/apps/coder-system/coder/app/ssh-key-rotation/coder-ssh-rotation-token.sops.yaml` containing:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: coder-ssh-rotation-token
  namespace: coder-system
stringData:
  GITHUB_PAT: "<pat-with-admin:ssh_signing_key-scope>"
```

Encrypt with: `sops -e -i cluster/apps/coder-system/coder/app/ssh-key-rotation/coder-ssh-rotation-token.sops.yaml`

- [ ] **Step 4: User creates and encrypts all three secrets**

Wait for user to confirm secrets are created.

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/coder-system/coder/app/coder-secrets.sops.yaml cluster/apps/coder-system/coder/app/coder-ssh-signing-key.sops.yaml cluster/apps/authentik-system/authentik/app/authentik-coder-oauth.sops.yaml cluster/apps/coder-system/coder/app/ssh-key-rotation/coder-ssh-rotation-token.sops.yaml
git commit -m "feat(coder): add SOPS-encrypted secrets

Ref #NNN"
```

---

## Task 6: Authentik Blueprint and OIDC Credential Delivery

**Files:**
- Create: `cluster/apps/authentik-system/authentik/app/blueprints/coder-sso.yaml`
- Modify: `cluster/apps/authentik-system/authentik/app/kustomization.yaml`
- Modify: `cluster/apps/authentik-system/authentik/app/external-secrets-rbac.yaml`
- Create: `cluster/apps/coder-system/coder/app/authentik-secret-store.yaml`
- Create: `cluster/apps/coder-system/coder/app/coder-oauth-external-secret.yaml`
- Create: `cluster/apps/coder-system/coder/app/oauth-rotation-rbac.yaml`

- [ ] **Step 1: Research Coder OIDC callback path**

Use Context7 or WebFetch to verify the OIDC callback path for the target Coder version. Check `https://coder.com/docs/admin/users/oidc-auth`. The expected callback is `/api/v2/users/oidc/callback`.

- [ ] **Step 2: Create Authentik blueprint**

Create `cluster/apps/authentik-system/authentik/app/blueprints/coder-sso.yaml`:

```yaml
# yamllint disable-file
# yaml-language-server: $schema=https://raw.githubusercontent.com/goauthentik/authentik/refs/heads/main/blueprints/schema.json
---
version: 1
metadata:
  name: Coder SSO
entries:
  - id: coder_users_group
    model: authentik_core.group
    identifiers:
      name: Coder Users
    attrs:
      name: Coder Users

  - id: coder_provider
    model: authentik_providers_oauth2.oauth2provider
    identifiers:
      name: Coder
    attrs:
      authorization_flow:
        !Find [
          authentik_flows.flow,
          [slug, "default-provider-authorization-implicit-consent"],
        ]
      invalidation_flow:
        !Find [
          authentik_flows.flow,
          [slug, "default-provider-invalidation-flow"],
        ]
      client_type: confidential
      redirect_uris:
        - url: https://code.${EXTERNAL_DOMAIN}/api/v2/users/oidc/callback
          matching_mode: strict
      client_id: !Env CODER_OIDC_CLIENT_ID
      client_secret: !Env CODER_OIDC_CLIENT_SECRET
      property_mappings:
        - !Find [
            authentik_core.propertymapping,
            [name, "authentik default OAuth Mapping: OpenID 'openid'"],
          ]
        - !Find [
            authentik_core.propertymapping,
            [name, "authentik default OAuth Mapping: OpenID 'profile'"],
          ]
        - !Find [
            authentik_core.propertymapping,
            [name, "authentik default OAuth Mapping: OpenID 'email'"],
          ]

  - id: coder_application
    model: authentik_core.application
    identifiers:
      slug: coder
    attrs:
      name: Coder
      provider: !KeyOf coder_provider
      meta_launch_url: https://code.${EXTERNAL_DOMAIN}
      icon: https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/coder.png

  - model: authentik_policies.policybinding
    identifiers:
      target: !KeyOf coder_application
      order: 0
    attrs:
      group: !KeyOf coder_users_group
      negate: false
      enabled: true
      timeout: 30
```

- [ ] **Step 3: Register blueprint in Authentik kustomization**

Add to the `authentik-blueprints` ConfigMap `files:` list in `cluster/apps/authentik-system/authentik/app/kustomization.yaml`:

```yaml
      - blueprints/coder-sso.yaml
```

Also add the OIDC SOPS secret to the `resources:` list:

```yaml
  - ./authentik-coder-oauth.sops.yaml
```

- [ ] **Step 4: Add coder-oauth-reader RBAC in authentik-system**

Append to `cluster/apps/authentik-system/authentik/app/external-secrets-rbac.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/role-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: coder-oauth-reader
  namespace: authentik-system
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["authentik-coder-oauth"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["authorization.k8s.io"]
    resources: ["selfsubjectrulesreviews"]
    verbs: ["create"]
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/rolebinding-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: coder-oauth-reader
  namespace: authentik-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: coder-oauth-reader
subjects:
  - kind: ServiceAccount
    name: authentik-secret-reader
    namespace: coder-system
```

- [ ] **Step 5: Create SecretStore in coder-system**

Create `cluster/apps/coder-system/coder/app/authentik-secret-store.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/serviceaccount-v1.json
apiVersion: v1
kind: ServiceAccount
metadata:
  name: authentik-secret-reader
  namespace: coder-system
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/external-secrets.io/secretstore_v1.json
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: coder-oauth-store
  namespace: coder-system
spec:
  provider:
    kubernetes:
      remoteNamespace: authentik-system
      server:
        url: "https://kubernetes.default.svc"
        caProvider:
          type: ConfigMap
          name: kube-root-ca.crt
          key: ca.crt
      auth:
        serviceAccount:
          name: authentik-secret-reader
```

- [ ] **Step 6: Create ExternalSecret for OIDC creds**

Create `cluster/apps/coder-system/coder/app/coder-oauth-external-secret.yaml`:

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: coder-oauth-credentials
  namespace: coder-system
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: SecretStore
    name: coder-oauth-store
  target:
    name: coder-oauth-credentials
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        CODER_OIDC_CLIENT_ID: "{{ .clientID }}"
        CODER_OIDC_CLIENT_SECRET: "{{ .clientSecret }}"
  data:
    - secretKey: clientID
      remoteRef:
        key: authentik-coder-oauth
        property: CODER_OIDC_CLIENT_ID
    - secretKey: clientSecret
      remoteRef:
        key: authentik-coder-oauth
        property: CODER_OIDC_CLIENT_SECRET
```

- [ ] **Step 7: Create oauth-rotation RBAC**

Create `cluster/apps/coder-system/coder/app/oauth-rotation-rbac.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/role-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: oauth-secret-rotation
  namespace: coder-system
rules:
  - apiGroups: ["external-secrets.io"]
    resources: ["externalsecrets"]
    resourceNames: ["coder-oauth-credentials"]
    verbs: ["get", "patch"]
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/rolebinding-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: oauth-secret-rotation
  namespace: coder-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: oauth-secret-rotation
subjects:
  - kind: ServiceAccount
    name: oauth-secret-rotation
    namespace: authentik-system
```

- [ ] **Step 8: Commit**

```bash
git add cluster/apps/authentik-system/authentik/app/blueprints/coder-sso.yaml \
  cluster/apps/authentik-system/authentik/app/kustomization.yaml \
  cluster/apps/authentik-system/authentik/app/external-secrets-rbac.yaml \
  cluster/apps/coder-system/coder/app/authentik-secret-store.yaml \
  cluster/apps/coder-system/coder/app/coder-oauth-external-secret.yaml \
  cluster/apps/coder-system/coder/app/oauth-rotation-rbac.yaml
git commit -m "feat(coder): add Authentik OIDC blueprint and credential delivery

Ref #NNN"
```

---

## Task 7: GitHub Token Integration

**Files:**
- Create: `cluster/apps/coder-system/coder/app/github-secret-store.yaml`
- Create: `cluster/apps/coder-system/coder/app/github-external-secret.yaml`
- Create: `cluster/apps/github-system/github-token-rotation/app/reader-role-binding-coder-system.yaml`
- Modify: `cluster/apps/github-system/github-token-rotation/app/cronjob.yaml`
- Modify: `cluster/apps/github-system/github-token-rotation/app/kustomization.yaml`

- [ ] **Step 1: Create SecretStore for github-system**

Create `cluster/apps/coder-system/coder/app/github-secret-store.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/serviceaccount-v1.json
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-secret-reader
  namespace: coder-system
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/external-secrets.io/secretstore_v1.json
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: github-secret-store
  namespace: coder-system
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

- [ ] **Step 2: Create ExternalSecret for GitHub token**

Create `cluster/apps/coder-system/coder/app/github-external-secret.yaml`:

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: github-bot-credentials
  namespace: coder-system
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: SecretStore
    name: github-secret-store
  target:
    name: github-bot-credentials
    creationPolicy: Owner
  data:
    - secretKey: git-credentials
      remoteRef:
        key: github-bot-credentials
        property: write-git-credentials
    - secretKey: access-token
      remoteRef:
        key: github-bot-credentials
        property: write-access-token
```

- [ ] **Step 3: Create reader RoleBinding in github-system**

Create `cluster/apps/github-system/github-token-rotation/app/reader-role-binding-coder-system.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/rolebinding-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-token-reader-coder-system
  namespace: github-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: github-token-reader
subjects:
  - kind: ServiceAccount
    name: github-secret-reader
    namespace: coder-system
```

- [ ] **Step 4: Register RoleBinding in github-system kustomization**

Add `- ./reader-role-binding-coder-system.yaml` to `cluster/apps/github-system/github-token-rotation/app/kustomization.yaml` resources list.

- [ ] **Step 5: Add coder-system to force_sync_consumers**

In `cluster/apps/github-system/github-token-rotation/app/cronjob.yaml`, update the `force_sync_consumers` loop to include `coder-system`:

Change:
```bash
for NS in claude-agents-write claude-agents-read github-mcp; do
```

To:
```bash
for NS in claude-agents-write claude-agents-read github-mcp coder-system; do
```

- [ ] **Step 6: Commit**

```bash
git add cluster/apps/coder-system/coder/app/github-secret-store.yaml \
  cluster/apps/coder-system/coder/app/github-external-secret.yaml \
  cluster/apps/github-system/github-token-rotation/app/reader-role-binding-coder-system.yaml \
  cluster/apps/github-system/github-token-rotation/app/kustomization.yaml \
  cluster/apps/github-system/github-token-rotation/app/cronjob.yaml
git commit -m "feat(coder): integrate with github-system token rotation

Ref #NNN"
```

---

## Task 8: Workspace RBAC (ServiceAccount + cluster-admin)

**Files:**
- Create: `cluster/apps/coder-system/coder/app/workspace-rbac.yaml`

- [ ] **Step 1: Create workspace RBAC**

Create `cluster/apps/coder-system/coder/app/workspace-rbac.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/serviceaccount-v1.json
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coder-workspace
  namespace: coder-system
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/clusterrolebinding-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: coder-workspace-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: coder-workspace
    namespace: coder-system
```

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/coder-system/coder/app/workspace-rbac.yaml
git commit -m "feat(coder): add workspace ServiceAccount with cluster-admin

Ref #NNN"
```

---

## Task 9: SSH Key Rotation CronJob

**Files:**
- Create: `cluster/apps/coder-system/coder/app/ssh-key-rotation/kustomization.yaml`
- Create: `cluster/apps/coder-system/coder/app/ssh-key-rotation/service-account.yaml`
- Create: `cluster/apps/coder-system/coder/app/ssh-key-rotation/role.yaml`
- Create: `cluster/apps/coder-system/coder/app/ssh-key-rotation/role-binding.yaml`
- Create: `cluster/apps/coder-system/coder/app/ssh-key-rotation/cronjob.yaml`

- [ ] **Step 1: Create kustomization**

Create `cluster/apps/coder-system/coder/app/ssh-key-rotation/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./coder-ssh-rotation-token.sops.yaml
  - ./service-account.yaml
  - ./role.yaml
  - ./role-binding.yaml
  - ./cronjob.yaml
```

- [ ] **Step 2: Create ServiceAccount**

Create `cluster/apps/coder-system/coder/app/ssh-key-rotation/service-account.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/serviceaccount-v1.json
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ssh-key-rotation
  namespace: coder-system
```

- [ ] **Step 3: Create Role**

Create `cluster/apps/coder-system/coder/app/ssh-key-rotation/role.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/role-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ssh-key-rotation
  namespace: coder-system
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["coder-ssh-signing-key"]
    verbs: ["get", "patch"]
```

- [ ] **Step 4: Create RoleBinding**

Create `cluster/apps/coder-system/coder/app/ssh-key-rotation/role-binding.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/rolebinding-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ssh-key-rotation
  namespace: coder-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ssh-key-rotation
subjects:
  - kind: ServiceAccount
    name: ssh-key-rotation
    namespace: coder-system
```

- [ ] **Step 5: Create CronJob**

Create `cluster/apps/coder-system/coder/app/ssh-key-rotation/cronjob.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/cronjob-batch-v1.json
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ssh-key-rotation
  namespace: coder-system
spec:
  schedule: "0 3 * * 1"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        metadata:
          labels:
            app: ssh-key-rotation
        spec:
          securityContext:
            runAsNonRoot: true
            runAsUser: 10001
            runAsGroup: 10001
          serviceAccountName: ssh-key-rotation
          containers:
            - name: rotate-ssh-key
              image: alpine/k8s:1.35.3@sha256:097aa60cbef561146757c7494468e9d7b04d843597ad1a1515ed09d0708c8014
              command:
                - /bin/sh
                - -c
                - |
                  set -e

                  echo "=== SSH signing key rotation ==="

                  # Generate new SSH key pair
                  ssh-keygen -t ed25519 -f /tmp/id_ed25519 -N "" -C "coder-workspace-signing-key"
                  PUB_KEY=$$(cat /tmp/id_ed25519.pub)
                  echo "New key generated"

                  # Add new signing key to GitHub
                  echo "Adding new signing key to GitHub..."
                  NEW_KEY_ID=$$(curl -s -X POST \
                    "https://api.github.com/user/ssh_signing_keys" \
                    -H "Authorization: token $${GITHUB_PAT}" \
                    -H "Accept: application/vnd.github+json" \
                    -H "X-GitHub-Api-Version: 2022-11-28" \
                    -d "{\"key\": \"$${PUB_KEY}\", \"title\": \"coder-workspace-signing-$$(date +%Y%m%d)\"}" \
                    | jq -r '.id')

                  if [ -z "$${NEW_KEY_ID}" ] || [ "$${NEW_KEY_ID}" = "null" ]; then
                    echo "ERROR: Failed to add new signing key to GitHub"
                    exit 1
                  fi
                  echo "New signing key added with ID: $${NEW_KEY_ID}"

                  # List existing signing keys and remove old ones with our prefix
                  echo "Cleaning up old signing keys..."
                  curl -s \
                    "https://api.github.com/user/ssh_signing_keys?per_page=100" \
                    -H "Authorization: token $${GITHUB_PAT}" \
                    -H "Accept: application/vnd.github+json" \
                    -H "X-GitHub-Api-Version: 2022-11-28" \
                    | jq -r ".[] | select(.title | startswith(\"coder-workspace-signing-\")) | select(.id != $${NEW_KEY_ID}) | .id" \
                    | while read OLD_ID; do
                        echo "Removing old key ID: $${OLD_ID}"
                        curl -s -X DELETE \
                          "https://api.github.com/user/ssh_signing_keys/$${OLD_ID}" \
                          -H "Authorization: token $${GITHUB_PAT}" \
                          -H "Accept: application/vnd.github+json" \
                          -H "X-GitHub-Api-Version: 2022-11-28"
                      done

                  # Update Kubernetes secret with new key pair
                  echo "Updating Kubernetes secret..."
                  PRIV_KEY=$$(cat /tmp/id_ed25519 | base64 -w0)
                  PUB_KEY_B64=$$(echo -n "$${PUB_KEY}" | base64 -w0)
                  kubectl patch secret coder-ssh-signing-key -n coder-system \
                    --type='json' \
                    -p="[{\"op\": \"replace\", \"path\": \"/data/id_ed25519\", \"value\": \"$${PRIV_KEY}\"},{\"op\": \"replace\", \"path\": \"/data/id_ed25519.pub\", \"value\": \"$${PUB_KEY_B64}\"}]"

                  # Clean up
                  rm -f /tmp/id_ed25519 /tmp/id_ed25519.pub

                  echo "=== SSH signing key rotation complete ==="
              env:
                - name: GITHUB_PAT
                  valueFrom:
                    secretKeyRef:
                      name: coder-ssh-rotation-token
                      key: GITHUB_PAT
              resources:
                requests:
                  cpu: 10m
                  memory: 32Mi
                limits:
                  cpu: 100m
                  memory: 128Mi
              volumeMounts:
                - name: tmp
                  mountPath: /tmp
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
          volumes:
            - name: tmp
              emptyDir:
                medium: Memory
                sizeLimit: 64Mi
          restartPolicy: OnFailure
```

- [ ] **Step 6: Commit**

```bash
git add cluster/apps/coder-system/coder/app/ssh-key-rotation/
git commit -m "feat(coder): add SSH signing key rotation CronJob

Ref #NNN"
```

---

## Task 10: Coder HelmRelease and Values

**Files:**
- Create: `cluster/apps/coder-system/coder/app/release.yaml`
- Create: `cluster/apps/coder-system/coder/app/values.yaml`
- Create: `cluster/apps/coder-system/coder/app/kustomizeconfig.yaml`

- [ ] **Step 1: Research Coder Helm chart values**

Use Context7 or WebFetch to get the latest Coder Helm chart values. Check:
- `https://raw.githubusercontent.com/coder/coder/main/helm/coder/values.yaml`
- Coder docs for OIDC configuration via environment variables

Key Coder env vars for OIDC: `CODER_OIDC_ISSUER_URL`, `CODER_OIDC_CLIENT_ID`, `CODER_OIDC_CLIENT_SECRET`, `CODER_OIDC_SCOPES`, `CODER_OIDC_SIGN_IN_TEXT`, `CODER_OIDC_ICON_URL`.

Key Coder env vars for DB: `CODER_PG_CONNECTION_URL`.

Key Coder env vars for access: `CODER_ACCESS_URL`, `CODER_WILDCARD_ACCESS_URL`.

- [ ] **Step 2: Create HelmRelease**

Create `cluster/apps/coder-system/coder/app/release.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas-cjso.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: coder
spec:
  chart:
    spec:
      chart: coder
      version: "2.30.6"
      sourceRef:
        kind: HelmRepository
        name: coder-charts
        namespace: flux-system
  interval: 4h
  valuesFrom:
    - kind: ConfigMap
      name: coder-values
```

Note: The exact chart version should be verified from `https://helm.coder.com/v2` during implementation. OIDC client ID/secret are injected via `valueFrom.secretKeyRef` in the env array in `values.yaml` rather than through HelmRelease `valuesFrom` to avoid fragile indexed array paths.

- [ ] **Step 3: Create values.yaml**

Create `cluster/apps/coder-system/coder/app/values.yaml`. The exact structure depends on the upstream chart — research during implementation. Expected structure:

```yaml
coder:
  env:
    - name: CODER_ACCESS_URL
      value: "https://code.${EXTERNAL_DOMAIN}"
    - name: CODER_PG_CONNECTION_URL
      valueFrom:
        secretKeyRef:
          name: coder-cnpg-cluster-app
          key: uri
    - name: CODER_OIDC_ISSUER_URL
      value: "https://auth.${EXTERNAL_DOMAIN}/application/o/coder/"
    - name: CODER_OIDC_CLIENT_ID
      valueFrom:
        secretKeyRef:
          name: coder-oauth-credentials
          key: CODER_OIDC_CLIENT_ID
    - name: CODER_OIDC_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: coder-oauth-credentials
          key: CODER_OIDC_CLIENT_SECRET
    - name: CODER_OIDC_SIGN_IN_TEXT
      value: "Sign in with Authentik"
    - name: CODER_OIDC_SCOPES
      value: "openid,profile,email"
  service:
    type: ClusterIP
```

- [ ] **Step 4: Create kustomizeconfig**

Create `cluster/apps/coder-system/coder/app/kustomizeconfig.yaml`:

```yaml
---
nameReference:
  - kind: ConfigMap
    version: v1
    fieldSpecs:
      - path: spec/valuesFrom/name
        kind: HelmRelease
```

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/coder-system/coder/app/release.yaml cluster/apps/coder-system/coder/app/values.yaml cluster/apps/coder-system/coder/app/kustomizeconfig.yaml
git commit -m "feat(coder): add HelmRelease and values

Ref #NNN"
```

---

## Task 11: Network Policies

**Files:**
- Create: `cluster/apps/coder-system/coder/app/network-policies.yaml`

- [ ] **Step 1: Create network policies**

Create `cluster/apps/coder-system/coder/app/network-policies.yaml`. Research the Coder Helm chart's label selectors and ports first — check what labels the Deployment uses and which ports it exposes.

```yaml
# DNS egress is handled by CiliumClusterwideNetworkPolicy allow-kube-dns-egress
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from Traefik to Coder control plane
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-traefik-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: coder
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: traefik
            k8s:app.kubernetes.io/name: traefik
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow Coder to reach CNPG PostgreSQL
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-cnpg-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: coder
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: coder-system
            k8s:cnpg.io/cluster: coder-cnpg-cluster
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow Coder to reach Authentik for OIDC token validation
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-authentik-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: coder
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: authentik-system
            k8s:app.kubernetes.io/name: authentik
      toPorts:
        - ports:
            - port: "9443"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow Coder to reach kube-api for workspace pod management
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-kube-api-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: coder
  egress:
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow Coder to reach world HTTPS (for devcontainer image pulls, Coder updates)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-world-https-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: coder
  egress:
    - toEntities:
        - world
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow metrics scraping from vmagent
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-metrics-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: coder
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            k8s:app.kubernetes.io/name: vmagent
      toPorts:
        - ports:
            - port: "2112"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# =============================================================================
# CNPG PostgreSQL Cluster Policies
# =============================================================================
# Allow ingress from Coder app for database connections
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-cnpg-coder-ingress
spec:
  endpointSelector:
    matchLabels:
      cnpg.io/cluster: coder-cnpg-cluster
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: coder-system
            k8s:app.kubernetes.io/name: coder
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow S3 backup uploads via Barman cloud plugin
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-cnpg-world-https-egress
spec:
  endpointSelector:
    matchLabels:
      cnpg.io/cluster: coder-cnpg-cluster
  egress:
    - toEntities:
        - world
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow metrics scraping from vmagent
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-cnpg-metrics-ingress
spec:
  endpointSelector:
    matchLabels:
      cnpg.io/cluster: coder-cnpg-cluster
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            k8s:app.kubernetes.io/name: vmagent
      toPorts:
        - ports:
            - port: "9187"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow CNPG operator access for cluster management
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-cnpg-operator-ingress
spec:
  endpointSelector:
    matchLabels:
      cnpg.io/cluster: coder-cnpg-cluster
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: cnpg-system
            k8s:app.kubernetes.io/name: cloudnative-pg
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow kube-api egress for cluster coordination
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-cnpg-kube-api-egress
spec:
  endpointSelector:
    matchLabels:
      cnpg.io/cluster: coder-cnpg-cluster
  egress:
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to Barman cloud plugin for backup operations
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-cnpg-barman-egress
spec:
  endpointSelector:
    matchLabels:
      cnpg.io/cluster: coder-cnpg-cluster
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: cnpg-system
            k8s:app.kubernetes.io/name: plugin-barman-cloud
      toPorts:
        - ports:
            - port: "9090"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow internal CNPG cluster communication for replication and status
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-cnpg-internal-cluster
spec:
  endpointSelector:
    matchLabels:
      cnpg.io/cluster: coder-cnpg-cluster
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: coder-system
            k8s:cnpg.io/cluster: coder-cnpg-cluster
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
            - port: "8000"
              protocol: TCP
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: coder-system
            k8s:cnpg.io/cluster: coder-cnpg-cluster
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
            - port: "8000"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# =============================================================================
# Workspace Pod Policies
# =============================================================================
# Workspace pods need broad egress for development tools
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-workspace-kube-api-egress
spec:
  endpointSelector:
    matchLabels:
      app: coder-workspace
  egress:
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow workspace pods to reach the internet (git, npm, pip, container pulls)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-workspace-world-egress
spec:
  endpointSelector:
    matchLabels:
      app: coder-workspace
  egress:
    - toEntities:
        - world
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
            - port: "80"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow workspace pods to reach Talos API
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-workspace-talos-egress
spec:
  endpointSelector:
    matchLabels:
      app: coder-workspace
  egress:
    - toCIDR:
        - "0.0.0.0/0"
      toPorts:
        - ports:
            - port: "50000"
              protocol: TCP
```

Note: The workspace pod label selector (`app: coder-workspace`) depends on what labels the Coder Terraform template assigns. Adjust during implementation after creating the template (Task 14). The Talos API port (50000) and CIDR should be verified against the cluster's Talos configuration.

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/coder-system/coder/app/network-policies.yaml
git commit -m "feat(coder): add CiliumNetworkPolicy for all components

Ref #NNN"
```

---

## Task 12: VPA

**Files:**
- Create: `cluster/apps/coder-system/coder/app/vpa.yaml`

- [ ] **Step 1: Research Coder Deployment name and container name**

Check the Coder Helm chart templates to find the Deployment name and container name. Expected: Deployment `coder`, container `coder`.

- [ ] **Step 2: Create VPA**

Create `cluster/apps/coder-system/coder/app/vpa.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: coder
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: coder
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: coder
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          memory: 2Gi
```

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/coder-system/coder/app/vpa.yaml
git commit -m "feat(coder): add VPA (recommendation-only)

Ref #NNN"
```

---

## Task 13: App Kustomization, Ingress, and Descheduler

**Files:**
- Create: `cluster/apps/coder-system/coder/app/kustomization.yaml`
- Create: `cluster/apps/traefik/traefik/ingress/coder-system/kustomization.yaml`
- Create: `cluster/apps/traefik/traefik/ingress/coder-system/ingress-routes.yaml`
- Create: `cluster/apps/traefik/traefik/ingress/coder-system/certificates.yaml`
- Modify: `cluster/apps/traefik/traefik/ingress/kustomization.yaml`
- Modify: `cluster/apps/traefik/traefik/ks.yaml`
- Modify: `cluster/apps/kube-system/descheduler/app/values.yaml`

- [ ] **Step 1: Create app kustomization**

Create `cluster/apps/coder-system/coder/app/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./coder-secrets.sops.yaml
  - ./coder-ssh-signing-key.sops.yaml
  - ./coder-cnpg-cluster.yaml
  - ./coder-cnpg-object-stores.yaml
  - ./coder-cnpg-scheduled-backups.yaml
  - ./authentik-secret-store.yaml
  - ./coder-oauth-external-secret.yaml
  - ./oauth-rotation-rbac.yaml
  - ./github-secret-store.yaml
  - ./github-external-secret.yaml
  - ./workspace-rbac.yaml
  - ./ssh-key-rotation
  - ./network-policies.yaml
  - ./release.yaml
  - ./vpa.yaml
configMapGenerator:
  - name: coder-values
    namespace: coder-system
    files:
      - values.yaml
configurations:
  - ./kustomizeconfig.yaml
```

- [ ] **Step 2: Create ingress kustomization**

Create `cluster/apps/traefik/traefik/ingress/coder-system/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base/compress.yaml
  - ./certificates.yaml
  - ./ingress-routes.yaml
patches:
  - target:
      kind: Middleware
      name: compress
    patch: |
      - op: replace
        path: /metadata/namespace
        value: coder-system
```

Note: The `compress` middleware must be imported from `../base/` and patched to the `coder-system` namespace. This is the established pattern — see `firefly-iii/kustomization.yaml` for reference.

- [ ] **Step 3: Create IngressRoute**

Create `cluster/apps/traefik/traefik/ingress/coder-system/ingress-routes.yaml`:

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/traefik.io/ingressroute_v1alpha1.json
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: ingress-routes-wan-https
  namespace: coder-system
  annotations:
    cert-manager.io/cluster-issuer: ${CLUSTER_ISSUER}
    external-dns.alpha.kubernetes.io/hostname: code.${EXTERNAL_DOMAIN}
spec:
  entryPoints:
    - websecure
  routes:
    - kind: Rule
      match: Host(`code.${EXTERNAL_DOMAIN}`)
      middlewares:
        - name: compress
      services:
        - name: coder
          namespace: coder-system
          passHostHeader: true
          port: 8080
  tls:
    secretName: "code-${EXTERNAL_DOMAIN/./-}-tls"
```

Note: Verify the Coder Service port (expected 8080) from the Helm chart during implementation.

- [ ] **Step 4: Create Certificate**

Create `cluster/apps/traefik/traefik/ingress/coder-system/certificates.yaml`:

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/cert-manager.io/certificate_v1.json
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: "code-${EXTERNAL_DOMAIN/./-}"
  namespace: coder-system
spec:
  secretName: "code-${EXTERNAL_DOMAIN/./-}-tls"
  issuerRef:
    name: ${CLUSTER_ISSUER}
    kind: ClusterIssuer
  dnsNames:
    - "code.${EXTERNAL_DOMAIN}"
```

- [ ] **Step 5: Register ingress directory**

Add `- ./coder-system` to `cluster/apps/traefik/traefik/ingress/kustomization.yaml` resources list.

- [ ] **Step 6: Add coder to traefik-ingress dependsOn**

Add `- name: coder` to the `traefik-ingress` Kustomization's `dependsOn` list in `cluster/apps/traefik/traefik/ks.yaml`.

- [ ] **Step 7: Add descheduler exclusion**

Add `coder-system` to each per-plugin `namespaces.exclude` list in `cluster/apps/kube-system/descheduler/app/values.yaml`.

- [ ] **Step 8: Commit**

```bash
git add cluster/apps/coder-system/coder/app/kustomization.yaml \
  cluster/apps/traefik/traefik/ingress/coder-system/ \
  cluster/apps/traefik/traefik/ingress/kustomization.yaml \
  cluster/apps/traefik/traefik/ks.yaml \
  cluster/apps/kube-system/descheduler/app/values.yaml
git commit -m "feat(coder): add app kustomization, ingress, and descheduler exclusion

Ref #NNN"
```

---

## Task 14: Coder Terraform Template

**Files:**
- Create: `coder/templates/devcontainer/main.tf`
- Create: `coder/templates/devcontainer/README.md`

- [ ] **Step 1: Research Coder Kubernetes devcontainer template**

Fetch the official template from Coder's registry:

```bash
gh search code "kubernetes-devcontainer" --repo coder/coder --language hcl
```

Or use WebFetch: `https://raw.githubusercontent.com/coder/coder/main/examples/templates/kubernetes-devcontainer/main.tf`

Also check the Coder template registry: `https://registry.coder.com/templates/coder/kubernetes-devcontainer`

- [ ] **Step 2: Create Terraform template**

Create `coder/templates/devcontainer/main.tf`. This is based on the official Coder kubernetes-devcontainer template, customized for this cluster:

The template should include:
- `coder_parameter` for git repo URL
- `kubernetes_persistent_volume_claim` for `/workspaces` and `/home/vscode`
- `kubernetes_pod` with:
  - `service_account_name = "coder-workspace"`
  - `security_context` with privileged mode (or specific caps — research first)
  - Volume mounts for `coder-secrets` (SSH key, talosconfig, terraform creds)
  - Volume mount for `github-bot-credentials` (git credentials)
  - Env vars from `coder-secrets` (ANTHROPIC_API_KEY)
  - Storage class `rbd-fast-delete`
  - Resource requests/limits appropriate for development workloads
- `coder_agent` with devcontainer support enabled

The exact Terraform code depends heavily on the upstream template structure — adapt from the official template during implementation rather than writing from scratch.

- [ ] **Step 3: Create README**

Create `coder/templates/devcontainer/README.md`:

```markdown
# Coder Devcontainer Template

Kubernetes workspace template for Coder that builds from `devcontainer.json`.

## Usage

Push to Coder:

    coder templates push devcontainer --directory .

## Features

- Builds from any repo's `.devcontainer/devcontainer.json`
- Docker-in-Docker for MegaLinter and container builds
- cluster-admin ServiceAccount for kubectl/helm/flux
- SSH signing key for verified git commits
- GitHub App token for git clone/push (rotated hourly)
- Talosconfig and Terraform credentials mounted

## Secrets Required

The following Kubernetes Secrets must exist in `coder-system`:

- `coder-secrets` — SSH signing key, talosconfig, terraform creds, API keys
- `github-bot-credentials` — GitHub App installation token (managed by github-system)
```

- [ ] **Step 4: Commit**

```bash
git add coder/templates/devcontainer/
git commit -m "feat(coder): add Terraform workspace template

Ref #NNN"
```

---

## Task 15: Add Coder to Authentik OAuth Rotation

**Files:**
- Modify: `cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/cronjob.yaml` (add coder-system to consumer list)
- Modify: `cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/role.yaml` (add `authentik-coder-oauth` to resourceNames)

- [ ] **Step 1: Read the existing oauth-secret-rotation files**

Read `cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/` to understand the current structure — specifically the CronJob's consumer loop and the Role's `resourceNames` list.

- [ ] **Step 2: Add `authentik-coder-oauth` to the rotation Role**

In `cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/role.yaml`, add `authentik-coder-oauth` to the `resourceNames` list so the rotation ServiceAccount can read/patch the Coder OIDC secret.

- [ ] **Step 3: Add Coder to the CronJob rotation calls**

In `cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/cronjob.yaml`, add a new `rotate_oauth` call for Coder following the existing pattern for Headlamp. Expected call signature:

```bash
rotate_oauth "Coder" "authentik-coder-oauth" "CODER_OIDC_CLIENT_SECRET" "coder-oauth-credentials" "coder-system"
```

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/cronjob.yaml \
  cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/role.yaml
git commit -m "feat(coder): add to Authentik oauth-secret-rotation

Ref #NNN"
```

---

## Task 16: Run qa-validator

- [ ] **Step 1: Run qa-validator**

Run the qa-validator agent on all changes before pushing. Fix any issues found.

- [ ] **Step 2: Fix any issues and re-run**

If qa-validator reports issues, fix them and re-run until clean.

- [ ] **Step 3: Final commit if fixes were needed**

```bash
git add <fixed-files>
git commit -m "fix(coder): address qa-validator findings

Ref #NNN"
```

---

## Task 17: Push and Validate

- [ ] **Step 1: User pushes to main**

User pushes all commits to main.

- [ ] **Step 2: Run cluster-validator**

After push, run cluster-validator to verify Flux reconciles successfully. Check:
- Coder HelmRelease is ready
- CNPG cluster is healthy
- ExternalSecrets are synced
- Network policies are applied
- IngressRoute and Certificate are created

- [ ] **Step 3: Fix any deployment issues**

If cluster-validator finds issues, apply fixes, commit, and re-push.

---

## Task 18: Post-Deploy Configuration

- [ ] **Step 1: Push Coder template**

From a workspace or local dev container:

```bash
coder templates push devcontainer --directory coder/templates/devcontainer/
```

- [ ] **Step 2: Add user to Coder Users group in Authentik**

Log into Authentik admin, add the user to the "Coder Users" group.

- [ ] **Step 3: Create first workspace**

Log into Coder at `code.${EXTERNAL_DOMAIN}`, create a workspace pointing to the `spruyt-labs` repo, and verify:
- Devcontainer builds successfully
- Docker-in-Docker works (`docker run hello-world`)
- kubectl works (`kubectl get nodes`)
- Git clone/push works with GitHub App token
- Git commits are signed and verified on GitHub
- Claude CLI is available and authenticated

- [ ] **Step 4: Test from phone**

Access `code.${EXTERNAL_DOMAIN}` from a mobile browser, verify the VS Code interface is usable.
