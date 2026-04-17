# Coder Workspaces Namespace Split — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Coder workspace pods from `coder-system` (PSA=baseline) into a new `coder-workspaces` namespace (PSA=privileged), keeping control plane unchanged, enabling `privileged: true` workspaces inside Kata VMs so `podman run hello-world` and `./lint.sh` succeed.

**Architecture:** Kata VM remains the hard boundary. PSA=privileged scoped only to the new workspace namespace. Kyverno restricts who may create privileged pods in that namespace to the `coder-workspace` ServiceAccount. NetworkPolicies stay permissive on workspace egress (world + cluster), with each consumed MCP self-gating ingress.

**Tech Stack:** FluxCD, Kustomize, Kata Containers, Cilium CNP, Kyverno, ExternalSecrets, Terraform (Coder template), SOPS/Age.

**Spec:** `docs/superpowers/specs/2026-04-17-coder-workspaces-namespace-split-design.md`

**Ref:** [#977](https://github.com/anthony-spruyt/spruyt-labs/issues/977). Probe evidence from abandoned Option C: commits `f4d9ae43`, `c4e5e048`, `322ff1de`.

---

## File Structure

### New files

| Path | Responsibility |
| ---- | -------------- |
| `cluster/apps/coder-workspaces/kustomization.yaml` | Namespace wrapper kustomization (lists namespace.yaml + sub-ks files). |
| `cluster/apps/coder-workspaces/namespace.yaml` | `coder-workspaces` ns with PSA=privileged and descheduler-exclude. |
| `cluster/apps/coder-workspaces/workspace-rbac/ks.yaml` | Flux Kustomization. |
| `cluster/apps/coder-workspaces/workspace-rbac/app/kustomization.yaml` | |
| `cluster/apps/coder-workspaces/workspace-rbac/app/workspace-rbac.yaml` | Moved SA + CRB. |
| `cluster/apps/coder-workspaces/network-policies/ks.yaml` | Flux Kustomization for CNPs. |
| `cluster/apps/coder-workspaces/network-policies/app/kustomization.yaml` | |
| `cluster/apps/coder-workspaces/network-policies/app/network-policies.yaml` | Workspace CNPs relocated from `coder-system/coder/app/network-policies.yaml`. |
| `cluster/apps/coder-workspaces/external-secrets/ks.yaml` | Flux Kustomization. |
| `cluster/apps/coder-workspaces/external-secrets/app/kustomization.yaml` | |
| `cluster/apps/coder-workspaces/external-secrets/app/coder-workspace-env.sops.yaml` | Moved from `coder-system/coder/app/`. |
| `cluster/apps/coder-workspaces/external-secrets/app/coder-talosconfig.sops.yaml` | Moved. |
| `cluster/apps/coder-workspaces/external-secrets/app/coder-ssh-signing-key.sops.yaml` | Moved. |
| `cluster/apps/coder-workspaces/external-secrets/app/coder-terraform-credentials.sops.yaml` | Moved. |
| `cluster/apps/coder-workspaces/external-secrets/app/authentik-secret-store.yaml` | New mirror of the secret store (ExternalSecret references ClusterSecretStore or namespace SecretStore). |
| `cluster/apps/coder-workspaces/kyverno-policy/ks.yaml` | Flux Kustomization. |
| `cluster/apps/coder-workspaces/kyverno-policy/app/kustomization.yaml` | |
| `cluster/apps/coder-workspaces/kyverno-policy/app/restrict-privileged-to-coder-workspace-sa.yaml` | Kyverno ClusterPolicy. |
| `hack/kata-fuse-probe/probe.sh` + `manifest.yaml` | Pre-flight: verify `privileged: true` + Kata exposes `/dev/fuse`. |

### Modified files

| Path | Change |
| ---- | ------ |
| `cluster/apps/kustomization.yaml` | Append `- ./coder-workspaces`. |
| `cluster/apps/coder-system/coder/app/workspace-rbac.yaml` | **Delete** (moved). |
| `cluster/apps/coder-system/coder/app/network-policies.yaml` | Remove every CNP whose `endpointSelector.matchLabels` is `app.kubernetes.io/name: coder-workspace` (they're relocating). |
| `cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml` | **Delete** (moved). |
| `cluster/apps/coder-system/coder/app/coder-talosconfig.sops.yaml` | **Delete** (moved). |
| `cluster/apps/coder-system/coder/app/coder-ssh-signing-key.sops.yaml` | **Delete** (moved). |
| `cluster/apps/coder-system/coder/app/coder-terraform-credentials.sops.yaml` | **Delete** (moved). |
| `cluster/apps/coder-system/coder/app/kustomization.yaml` | Remove the deleted files from `resources:`. |
| `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml` | `allow-coder-workspace-ingress`: retarget ns. |
| `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml` | Same retarget. |
| `cluster/apps/github-mcp/github-mcp-server/app/network-policies.yaml` | Same retarget. |
| `cluster/apps/discord-mcp/discord-mcp/app/network-policies.yaml` | Same retarget. |
| `cluster/apps/brave-search-mcp/brave-search-mcp/app/network-policies.yaml` | Same retarget. |
| `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf` | `local.namespace = "coder-workspaces"`; `security_context.privileged = true`; `startup_script` adds `/run/user/1000` + `XDG_RUNTIME_DIR`. |
| `.devcontainer/post-create.sh` | Detect Coder workspace; write `~/.config/containers/storage.conf` with `fuse-overlayfs` or `vfs` driver based on `/dev/fuse`. |
| `lint.sh` | Docker-shim detection; if `/usr/bin/docker` is a podman wrapper and sudo works, use rootful podman. |
| `.trivyignore.yaml` | Add scoped AVD-KSV entries for `coder-workspaces/**`. |

---

## Task 1: Pre-flight — verify `/dev/fuse` under privileged Kata

**Why first:** if privileged Kata pods do NOT expose `/dev/fuse`, we need an extra kata annotation or device-cgroup config, which changes the template. Spend 10 min confirming before committing 14 more tasks.

**Files:**
- Create: `hack/kata-fuse-probe/manifest.yaml`
- Create: `hack/kata-fuse-probe/probe.sh`

- [ ] **Step 1: Write `hack/kata-fuse-probe/manifest.yaml`**

```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: kata-fuse-probe
  labels:
    app.kubernetes.io/name: kata-fuse-probe
spec:
  runtimeClassName: kata
  restartPolicy: Never
  nodeSelector:
    kata.spruyt-labs/ready: "true"
  containers:
    - name: probe
      image: docker.io/library/fedora:41
      command: ["sleep", "600"]
      securityContext:
        privileged: true
```

- [ ] **Step 2: Write `hack/kata-fuse-probe/probe.sh` (+ chmod +x)**

```bash
#!/usr/bin/env bash
set -euo pipefail

NS=default
MANIFEST="$(dirname "$0")/manifest.yaml"

# Requires a namespace that allows privileged: relax default ns briefly.
kubectl label --overwrite ns "${NS}" \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/warn=privileged

trap '
  kubectl -n '"${NS}"' delete -f '"${MANIFEST}"' --ignore-not-found --wait=false
  kubectl label --overwrite ns '"${NS}"' \
    pod-security.kubernetes.io/enforce=baseline \
    pod-security.kubernetes.io/warn=baseline
' EXIT

kubectl -n "${NS}" apply -f "${MANIFEST}"
kubectl -n "${NS}" wait --for=condition=Ready pod/kata-fuse-probe --timeout=120s

echo "--- /dev/fuse ---"
kubectl -n "${NS}" exec kata-fuse-probe -- sh -c 'ls -l /dev/fuse 2>&1; echo rc=$?'
echo "--- /dev/net/tun ---"
kubectl -n "${NS}" exec kata-fuse-probe -- sh -c 'ls -l /dev/net/tun 2>&1; echo rc=$?'
echo "--- fuse-overlayfs smoketest ---"
kubectl -n "${NS}" exec kata-fuse-probe -- sh -c '
  dnf -qy install fuse-overlayfs fuse > /dev/null 2>&1
  mkdir -p /tmp/{lower,upper,work,merged}
  fuse-overlayfs -o lowerdir=/tmp/lower,upperdir=/tmp/upper,workdir=/tmp/work /tmp/merged 2>&1
  echo rc=$?
  mountpoint /tmp/merged 2>&1
'
```

- [ ] **Step 3: Run probe**

```bash
./hack/kata-fuse-probe/probe.sh
```

Expected (all three):
1. `/dev/fuse` present (char device, major 10, minor 229).
2. `/dev/net/tun` present.
3. `fuse-overlayfs` mount rc=0, `mountpoint` reports yes.

- [ ] **Step 4: Decision gate**

- All green → proceed to Task 2. Storage driver = `fuse-overlayfs`.
- Any red → stop, surface to user. Likely remediation: add `io.katacontainers.config.hypervisor.virtio_fs_extra_args` or a device-cgroup annotation to the workspace pod, OR fall back to `vfs` storage (slow but works). Adjust spec §6 before resuming.

- [ ] **Step 5: Commit the probe scripts (keep in tree as regression reproducer)**

```bash
git add hack/kata-fuse-probe/
git commit -m "test(coder): pre-flight probe for /dev/fuse under privileged kata

Ref #977"
```

Do NOT push yet.

---

## Task 2: Create `coder-workspaces` namespace scaffold

**Files:**
- Create: `cluster/apps/coder-workspaces/namespace.yaml`
- Create: `cluster/apps/coder-workspaces/kustomization.yaml`
- Modify: `cluster/apps/kustomization.yaml`

- [ ] **Step 1: Write `cluster/apps/coder-workspaces/namespace.yaml`**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/namespace-v1.json
apiVersion: v1
kind: Namespace
metadata:
  name: coder-workspaces
  labels:
    # privileged because workspace containers run with privileged: true.
    # Kata runtime provides the real isolation boundary; PSA at K8s layer
    # is guardrail, not the security primitive. Kyverno ClusterPolicy in
    # kyverno-policy/ restricts privileged pod creation here to the
    # coder-workspace ServiceAccount.
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
    descheduler.kubernetes.io/exclude: "true"
```

- [ ] **Step 2: Write `cluster/apps/coder-workspaces/kustomization.yaml`**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./workspace-rbac/ks.yaml
  - ./network-policies/ks.yaml
  - ./external-secrets/ks.yaml
  - ./kyverno-policy/ks.yaml
```

- [ ] **Step 3: Register in root apps kustomization**

Edit `cluster/apps/kustomization.yaml` — add `./coder-workspaces` next to `./coder-system` (keep alphabetical order):

```yaml
  - ./coder-system
  - ./coder-workspaces
```

- [ ] **Step 4: Add descheduler exclude to descheduler values**

Edit `cluster/apps/kube-system/descheduler/app/values.yaml`: add `coder-workspaces` to every plugin's `namespaces.exclude` list (same pattern as `coder-system`). Search for existing `coder-system` entries first — grep confirms positions to update:

```bash
grep -n 'coder-system' cluster/apps/kube-system/descheduler/app/values.yaml
```

Add `coder-workspaces` as a sibling entry on each match.

- [ ] **Step 5: Commit (do not push)**

```bash
git add cluster/apps/coder-workspaces/namespace.yaml \
        cluster/apps/coder-workspaces/kustomization.yaml \
        cluster/apps/kustomization.yaml \
        cluster/apps/kube-system/descheduler/app/values.yaml
git commit -m "feat(coder): scaffold coder-workspaces namespace (PSA=privileged)

Ref #977"
```

---

## Task 3: Move workspace RBAC

**Files:**
- Create: `cluster/apps/coder-workspaces/workspace-rbac/ks.yaml`
- Create: `cluster/apps/coder-workspaces/workspace-rbac/app/kustomization.yaml`
- Create: `cluster/apps/coder-workspaces/workspace-rbac/app/workspace-rbac.yaml`
- Delete: `cluster/apps/coder-system/coder/app/workspace-rbac.yaml`
- Modify: `cluster/apps/coder-system/coder/app/kustomization.yaml`

- [ ] **Step 1: Read source**

```bash
cat cluster/apps/coder-system/coder/app/workspace-rbac.yaml
```

The SA is cluster-scoped via a `ClusterRoleBinding` referencing a namespaced SA. Moving the SA changes the `subjects[0].namespace` on the CRB.

- [ ] **Step 2: Write the moved file — `cluster/apps/coder-workspaces/workspace-rbac/app/workspace-rbac.yaml`**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/serviceaccount-v1.json
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coder-workspace
  namespace: coder-workspaces
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
    namespace: coder-workspaces
```

- [ ] **Step 3: Write the app kustomization**

`cluster/apps/coder-workspaces/workspace-rbac/app/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./workspace-rbac.yaml
```

- [ ] **Step 4: Write the Flux Kustomization**

`cluster/apps/coder-workspaces/workspace-rbac/ks.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: coder-workspace-rbac
  namespace: flux-system
spec:
  targetNamespace: coder-workspaces
  commonMetadata:
    labels:
      app.kubernetes.io/name: coder-workspace-rbac
  dependsOn:
    - name: cluster-apps-coder-workspaces
  interval: 30m
  timeout: 5m
  path: ./cluster/apps/coder-workspaces/workspace-rbac/app
  prune: true
  retryInterval: 1m
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
```

> **Cross-check pattern first:** before writing Step 4, open any
> existing `ks.yaml` under `cluster/apps/coder-system/` (e.g.,
> `coder/ks.yaml`) and copy its Flux Kustomization conventions
> (naming, `dependsOn`, `postBuild.substituteFrom`, etc.). Update the
> template above to match. The `dependsOn` name above
> (`cluster-apps-coder-workspaces`) may not be correct for this
> repo's naming — adjust to match the one that installs the namespace
> kustomization from `cluster/apps/coder-workspaces/namespace.yaml`.

- [ ] **Step 5: Delete source file**

```bash
git rm cluster/apps/coder-system/coder/app/workspace-rbac.yaml
```

- [ ] **Step 6: Remove from `coder/app/kustomization.yaml`**

Edit `cluster/apps/coder-system/coder/app/kustomization.yaml` — remove the `- ./workspace-rbac.yaml` line from `resources:`.

- [ ] **Step 7: Commit**

```bash
git add cluster/apps/coder-workspaces/workspace-rbac/ \
        cluster/apps/coder-system/coder/app/kustomization.yaml
git commit -m "refactor(coder): move coder-workspace SA to coder-workspaces ns

Ref #977"
```

Do not push.

---

## Task 4: Split workspace CNPs out of coder-system

**Files:**
- Create: `cluster/apps/coder-workspaces/network-policies/ks.yaml`
- Create: `cluster/apps/coder-workspaces/network-policies/app/kustomization.yaml`
- Create: `cluster/apps/coder-workspaces/network-policies/app/network-policies.yaml`
- Modify: `cluster/apps/coder-system/coder/app/network-policies.yaml` (remove workspace CNPs)

- [ ] **Step 1: Identify workspace CNPs in `coder-system/coder/app/network-policies.yaml`**

Every CNP whose `endpointSelector.matchLabels.app.kubernetes.io/name` is `coder-workspace` belongs to the new namespace. From the audit these are:

- `allow-workspace-kube-api-egress`
- `allow-workspace-world-egress`
- `allow-workspace-traefik-egress`
- `allow-workspace-kubectl-mcp-egress`
- `allow-workspace-victoriametrics-mcp-egress`
- `allow-workspace-github-mcp-egress`
- `allow-workspace-discord-mcp-egress`
- `allow-workspace-brave-search-mcp-egress`
- `allow-workspace-nexus-egress`
- `allow-workspace-n8n-mcp-egress`
- `allow-workspace-homeassistant-mcp-egress`
- `allow-workspace-wireguard-tunnel` (spec's endpointSelector targets `coder-workspace` pods; ingress from `coder` in coder-system)

Plus two CNPs on the control-plane side that reference workspace pods (these STAY in coder-system but need their `fromEndpoints.k8s:io.kubernetes.pod.namespace` updated from `coder-system` to `coder-workspaces`):

- `allow-wireguard-tunnel` (coder-system side, endpointSelector: `coder`, fromEndpoints+toEndpoints reference `coder-workspace`). Update both its ingress `fromEndpoints.k8s:io.kubernetes.pod.namespace` and egress `toEndpoints.k8s:io.kubernetes.pod.namespace` to `coder-workspaces`.

- [ ] **Step 2: Write new `cluster/apps/coder-workspaces/network-policies/app/network-policies.yaml`**

Copy the 12 workspace CNPs verbatim from the source. For `allow-workspace-wireguard-tunnel`, update both its `egress.toEndpoints` and `ingress.fromEndpoints` `k8s:io.kubernetes.pod.namespace` from `coder-system` (current) to `coder-system` (unchanged — the peer is still `coder`).

Also add a header comment explaining the namespace:

```yaml
# Workspace pod CNPs for coder-workspaces namespace.
# Relocated from cluster/apps/coder-system/coder/app/network-policies.yaml.
# Pods in this ns carry label app.kubernetes.io/name: coder-workspace.
# DNS egress handled by CiliumClusterwideNetworkPolicy/allow-kube-dns-egress.
```

(Full content: copy each CNP definition block as-is; adjust the wireguard policy's peer ns if that value was `coder-system` — the peer `coder` pod still lives there so it stays `coder-system`.)

- [ ] **Step 3: Write `network-policies/app/kustomization.yaml`**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./network-policies.yaml
```

- [ ] **Step 4: Write `network-policies/ks.yaml`**

Mirror the workspace-rbac/ks.yaml pattern from Task 3. Same `dependsOn`, different `path`. Name: `coder-workspaces-network-policies`.

- [ ] **Step 5: Remove workspace CNPs from `coder-system/coder/app/network-policies.yaml`**

Delete the 12 CNPs whose `endpointSelector` is `coder-workspace`. KEEP `allow-wireguard-tunnel` (coder server side) but edit its `fromEndpoints.k8s:io.kubernetes.pod.namespace` + `toEndpoints.k8s:io.kubernetes.pod.namespace` from `coder-system` to `coder-workspaces`.

- [ ] **Step 6: Commit**

```bash
git add cluster/apps/coder-workspaces/network-policies/ \
        cluster/apps/coder-system/coder/app/network-policies.yaml
git commit -m "refactor(coder): split workspace CNPs into coder-workspaces ns

Workspace-targeted Cilium policies relocated; coder-system control-
plane policies retain references but update peer namespace.

Ref #977"
```

---

## Task 5: Retarget MCP ingress CNPs

**Files (modify):**
- `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml`
- `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml`
- `cluster/apps/github-mcp/github-mcp-server/app/network-policies.yaml`
- `cluster/apps/discord-mcp/discord-mcp/app/network-policies.yaml`
- `cluster/apps/brave-search-mcp/brave-search-mcp/app/network-policies.yaml`

Each file has an `allow-coder-workspace-ingress` CNP with hardcoded `k8s:io.kubernetes.pod.namespace: coder-system`. Retarget to `coder-workspaces`.

- [ ] **Step 1: Audit for any other CNPs referencing coder-workspace**

```bash
grep -rln 'coder-workspace' cluster/apps/ | grep network-polic
```

Expected: the 5 files above plus the coder-system files already modified in Task 4. If more appear, add them here.

- [ ] **Step 2: For each of the 5 files, edit the `allow-coder-workspace-ingress` CNP**

Change `k8s:io.kubernetes.pod.namespace: coder-system` → `k8s:io.kubernetes.pod.namespace: coder-workspaces` on the `fromEndpoints.matchLabels` line.

Leave every other CNP (Traefik ingress, kube-api egress, claude-agents ingress, etc.) untouched.

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml \
        cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml \
        cluster/apps/github-mcp/github-mcp-server/app/network-policies.yaml \
        cluster/apps/discord-mcp/discord-mcp/app/network-policies.yaml \
        cluster/apps/brave-search-mcp/brave-search-mcp/app/network-policies.yaml
git commit -m "refactor(mcp): retarget coder-workspace ingress to coder-workspaces ns

Ref #977"
```

---

## Task 6: Move workspace-scoped ExternalSecrets

**Files:**
- Create: `cluster/apps/coder-workspaces/external-secrets/ks.yaml`
- Create: `cluster/apps/coder-workspaces/external-secrets/app/kustomization.yaml`
- Move: `coder-system/coder/app/coder-workspace-env.sops.yaml` → new path
- Move: `coder-system/coder/app/coder-talosconfig.sops.yaml` → new path
- Move: `coder-system/coder/app/coder-ssh-signing-key.sops.yaml` → new path
- Move: `coder-system/coder/app/coder-terraform-credentials.sops.yaml` → new path
- Create: `cluster/apps/coder-workspaces/external-secrets/app/authentik-secret-store.yaml` (if the existing secret store in `coder-system/coder/app/authentik-secret-store.yaml` is a `SecretStore` not a `ClusterSecretStore` — verify first)
- Modify: `coder-system/coder/app/kustomization.yaml`

- [ ] **Step 1: Inspect the source secret store**

```bash
cat cluster/apps/coder-system/coder/app/authentik-secret-store.yaml
```

If it's `kind: SecretStore` (namespace-scoped), we need a sibling `SecretStore` in `coder-workspaces` for ExternalSecrets to resolve. If it's `kind: ClusterSecretStore`, reuse from new ns without mirroring.

- [ ] **Step 2a (if SecretStore): Create mirror**

Copy the file content to `cluster/apps/coder-workspaces/external-secrets/app/authentik-secret-store.yaml` with the metadata.namespace field removed (kustomization will apply `targetNamespace`) OR set to `coder-workspaces`. Keep the backend config identical.

- [ ] **Step 2b (if ClusterSecretStore): Skip mirror**

Move files in Steps 3-6 but no secret-store creation needed in new ns.

- [ ] **Step 3-6: Git move each SOPS file**

```bash
git mv cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml \
       cluster/apps/coder-workspaces/external-secrets/app/coder-workspace-env.sops.yaml
git mv cluster/apps/coder-system/coder/app/coder-talosconfig.sops.yaml \
       cluster/apps/coder-workspaces/external-secrets/app/coder-talosconfig.sops.yaml
git mv cluster/apps/coder-system/coder/app/coder-ssh-signing-key.sops.yaml \
       cluster/apps/coder-workspaces/external-secrets/app/coder-ssh-signing-key.sops.yaml
git mv cluster/apps/coder-system/coder/app/coder-terraform-credentials.sops.yaml \
       cluster/apps/coder-workspaces/external-secrets/app/coder-terraform-credentials.sops.yaml
```

> **Do NOT edit the SOPS ciphertext or decrypt.** The files stay
> encrypted. SOPS rules in `.sops.yaml` already match
> `cluster/apps/**` — the new path remains encrypted without further
> config.
>
> **Verify namespace inside the encrypted files:** ExternalSecrets
> have a `metadata.namespace` field that is NOT encrypted (SOPS
> encrypts values, not structural keys). Open each SOPS file with
> `sops <path>` — user must do this manually per
> `.claude/rules/01-constraints.md`. Claude: prepare an editing note
> for the user listing each file and the change
> (`metadata.namespace: coder-system` → `coder-workspaces`) but do
> NOT attempt to edit encrypted files yourself.

- [ ] **Step 7: Write `external-secrets/app/kustomization.yaml`**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./coder-workspace-env.sops.yaml
  - ./coder-talosconfig.sops.yaml
  - ./coder-ssh-signing-key.sops.yaml
  - ./coder-terraform-credentials.sops.yaml
  # Uncomment next line if Step 2a created a SecretStore mirror:
  # - ./authentik-secret-store.yaml
```

- [ ] **Step 8: Write `external-secrets/ks.yaml`**

Mirror pattern from Task 3's ks.yaml. Name: `coder-workspaces-external-secrets`. Critically — ensure SOPS decryption is configured on this Flux Kustomization (the existing coder-system Flux ks uses `spec.decryption.provider: sops` + `secretRef.name`). Copy that block verbatim from `cluster/apps/coder-system/coder/ks.yaml`.

- [ ] **Step 9: Remove moved files from `coder-system/coder/app/kustomization.yaml`**

Delete the four `- ./coder-*.sops.yaml` lines that correspond to moved files. Leave `coder-oauth-external-secret.yaml`, `coder-cnpg-credentials.sops.yaml`, etc. — those stay.

- [ ] **Step 10: Prepare user SOPS-edit instruction**

Write the editing note to `/tmp/coder-sops-edit-notes.md` (local, not committed):

```markdown
# Manual SOPS edits required

For each of these 4 files, run `sops <path>` and change `metadata.namespace`:
  old: coder-system
  new: coder-workspaces

Files:
1. cluster/apps/coder-workspaces/external-secrets/app/coder-workspace-env.sops.yaml
2. cluster/apps/coder-workspaces/external-secrets/app/coder-talosconfig.sops.yaml
3. cluster/apps/coder-workspaces/external-secrets/app/coder-ssh-signing-key.sops.yaml
4. cluster/apps/coder-workspaces/external-secrets/app/coder-terraform-credentials.sops.yaml
```

Report DONE_WITH_CONCERNS and surface this note to the user. They will open each file, edit, save. Then the implementer (next dispatch) commits.

- [ ] **Step 11 (after user completes SOPS edits): Commit**

```bash
git add cluster/apps/coder-workspaces/external-secrets/ \
        cluster/apps/coder-system/coder/app/kustomization.yaml
git commit -m "refactor(coder): move workspace ExternalSecrets to coder-workspaces ns

Ref #977"
```

---

## Task 7: Kyverno ClusterPolicy

**Files:**
- Create: `cluster/apps/coder-workspaces/kyverno-policy/ks.yaml`
- Create: `cluster/apps/coder-workspaces/kyverno-policy/app/kustomization.yaml`
- Create: `cluster/apps/coder-workspaces/kyverno-policy/app/restrict-privileged-to-coder-workspace-sa.yaml`

- [ ] **Step 1: Inspect existing Kyverno policies in the repo**

```bash
ls cluster/apps/kyverno/policies/
grep -rln 'kind: ClusterPolicy' cluster/apps/kyverno/policies/app/ | head
```

Copy any established style (validationFailureAction, background, admission).

- [ ] **Step 2: Write the policy**

`cluster/apps/coder-workspaces/kyverno-policy/app/restrict-privileged-to-coder-workspace-sa.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/kyverno/policy-reporter/main/schema/ClusterPolicy.json
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-privileged-to-coder-workspace-sa
  annotations:
    policies.kyverno.io/title: Restrict privileged pods in coder-workspaces
    policies.kyverno.io/subject: Pod
    policies.kyverno.io/description: >
      In the coder-workspaces namespace, privileged pods may only be created
      by the coder-workspace ServiceAccount. Defense in depth beyond PSA
      and the Kata VM boundary.
spec:
  validationFailureAction: Enforce
  background: false
  rules:
    - name: only-coder-workspace-sa-privileged
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [coder-workspaces]
      preconditions:
        any:
          - key: "{{ request.object.spec.containers[].securityContext.privileged || `[]` }}"
            operator: AnyIn
            value: [true]
      validate:
        message: "Privileged pods in coder-workspaces require ServiceAccount 'coder-workspace' (got {{ request.object.spec.serviceAccountName || 'default' }})"
        deny:
          conditions:
            all:
              - key: "{{ request.object.spec.serviceAccountName || 'default' }}"
                operator: NotEquals
                value: coder-workspace
```

> **Verify CEL/JMESPath syntax** against installed Kyverno version — `kubectl get deploy -n kyverno kyverno-admission-controller -o jsonpath='{.spec.template.spec.containers[0].image}'`. Kyverno ≥1.10 supports the above; older versions may need pattern-style rather than deny-conditions.

- [ ] **Step 3: Write `kyverno-policy/app/kustomization.yaml`**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./restrict-privileged-to-coder-workspace-sa.yaml
```

- [ ] **Step 4: Write `kyverno-policy/ks.yaml`**

Mirror Task 3 pattern. Name: `coder-workspaces-kyverno-policy`. `dependsOn` should include both the namespace and the Kyverno CRDs kustomization (find it via `grep -r 'name: cluster-apps-kyverno' cluster/flux`).

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/coder-workspaces/kyverno-policy/
git commit -m "feat(coder): Kyverno policy restricting privileged pods to coder-workspace SA

Ref #977"
```

---

## Task 8: Trivy suppressions

**Files:**
- Modify: `.trivyignore.yaml`

- [ ] **Step 1: Read current file**

```bash
cat .trivyignore.yaml
```

Identify the existing structure (single-list vs per-finding entries).

- [ ] **Step 2: Append scoped entries**

Add at end of file, following existing style. Example given current repo conventions:

```yaml
- id: AVD-KSV-0017  # Privileged container
  paths:
    - "cluster/apps/coder-workspaces/**"
  statement: |
    Workspace pods legitimately privileged. Defense in depth:
    (1) Kata VM boundary is the real isolation primitive;
    (2) Kyverno ClusterPolicy restricts privileged pods in this ns
        to the coder-workspace ServiceAccount;
    (3) namespace PSA=privileged scoped only to this namespace.
- id: AVD-KSV-0014  # Root filesystem is writable
  paths:
    - "cluster/apps/coder-workspaces/**"
  statement: |
    Workspaces need writable rootfs for dev workflows (package
    installs, build artefacts). Isolated by Kata VM.
```

If `task dev-env:lint` surfaces additional AVD IDs later, add them one-by-one with explicit rationale. Do NOT add broad wildcards.

- [ ] **Step 3: Commit**

```bash
git add .trivyignore.yaml
git commit -m "chore(trivy): scoped ignores for coder-workspaces privileged pods

Ref #977"
```

---

## Task 9: Update Coder template (main.tf)

**Files:**
- Modify: `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf`

Targeted edits only. Preserve everything else.

- [ ] **Step 1: Change namespace local**

Line 42: `namespace = "coder-system"` → `namespace = "coder-workspaces"`.

- [ ] **Step 2: Flip privileged**

Line ~449 in the `dev` container `security_context`:

```terraform
security_context {
  privileged                 = true
  allow_privilege_escalation = true
  read_only_root_filesystem  = false
  # No seccomp_profile here — privileged pods bypass; omit to avoid conflict.
}
```

Remove the `seccomp_profile { type = "RuntimeDefault" }` block if privileged=true rejects it (Kubernetes accepts the combo but some operators warn). Verify by running `terraform plan` locally if possible.

- [ ] **Step 3: Add XDG_RUNTIME_DIR setup to startup_script**

Find the `startup_script` block (search for `startup_script` in the file). Append these lines at the top of the script (after the shebang if present):

```bash
sudo mkdir -p /run/user/1000
sudo chown 1000:1000 /run/user/1000
export XDG_RUNTIME_DIR=/run/user/1000
```

- [ ] **Step 4: Verify pod labels still set `app.kubernetes.io/name: coder-workspace`**

Audit line 381 (`"app.kubernetes.io/name" = "coder-workspace"`) is still present in the pod spec template. It is — no change needed. This label is what MCP ingress CNPs match on.

- [ ] **Step 5: Audit any other hardcoded `coder-system` references in main.tf**

```bash
grep -n 'coder-system' cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf
```

Line 233 (inside a heredoc YAML string) references `namespace: coder-system` — inspect context. If it's a NetworkPolicy or similar rendered INTO the workspace at runtime, update it to `coder-workspaces`. If it's a reference to the Coder control plane (e.g., access URL), leave it.

- [ ] **Step 6: Commit**

```bash
git add cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf
git commit -m "feat(coder): move workspace pods to coder-workspaces ns + enable privileged

Workspaces now run privileged inside Kata VM. XDG_RUNTIME_DIR created
for rootful podman.

Ref #977"
```

---

## Task 10: Workspace consumer scripts

**Files:**
- Modify: `.devcontainer/post-create.sh`
- Modify: `lint.sh`

- [ ] **Step 1: Read current scripts**

```bash
cat .devcontainer/post-create.sh
cat lint.sh
```

- [ ] **Step 2: post-create.sh — podman storage detection**

Add near the top (after initial setup, before any podman calls):

```bash
# Configure podman storage driver based on /dev/fuse availability (Kata guest).
if [ -c /dev/fuse ]; then
  STORAGE_DRIVER="fuse-overlayfs"
else
  STORAGE_DRIVER="vfs"
fi
mkdir -p ~/.config/containers
cat > ~/.config/containers/storage.conf <<EOF
[storage]
driver = "${STORAGE_DRIVER}"
runroot = "/run/user/$(id -u)/containers"
graphroot = "${HOME}/.local/share/containers/storage"
EOF
```

Wrap in a Coder-workspace detection guard if the script runs outside Coder too:

```bash
if [ -n "${CODER_WORKSPACE_ID:-}" ]; then
  # ... the storage.conf block above ...
fi
```

- [ ] **Step 3: lint.sh — docker-shim/podman detection**

Find the block that currently calls `podman` (grep `podman` in the file). Replace with:

```bash
# Resolve container tool: prefer sudo podman (rootful) if /usr/bin/docker
# is a podman wrapper and sudo works without password prompt.
if sudo -n podman --version > /dev/null 2>&1; then
  CONTAINER_TOOL="sudo podman"
elif command -v podman > /dev/null 2>&1; then
  CONTAINER_TOOL="podman"
elif command -v docker > /dev/null 2>&1; then
  CONTAINER_TOOL="docker"
else
  echo "No container tool (podman/docker) available" >&2
  exit 1
fi
# ... use ${CONTAINER_TOOL} in subsequent commands ...
```

Adjust to the specific lines in the existing `lint.sh` — don't duplicate variable defs.

- [ ] **Step 4: Commit**

```bash
git add .devcontainer/post-create.sh lint.sh
git commit -m "fix(coder): workspace-side podman storage + lint.sh shim detection

Ref #977"
```

---

## Task 11: qa-validator + push

- [ ] **Step 1: Invoke qa-validator agent**

Scope: all files modified in Tasks 2-10 (plus the Task 1 hack/ additions).

- [ ] **Step 2: Fix any issues**

Apply fixes inline; re-run qa-validator.

- [ ] **Step 3: Push all commits**

```bash
git push
```

(Per user feedback, push is permitted; Flux webhook triggers reconcile.)

- [ ] **Step 4: Watch Flux reconcile**

```bash
flux get kustomizations -n flux-system | grep -E 'coder-system|coder-workspaces|kubectl-mcp|mcp-victoriametrics|github-mcp|discord-mcp|brave-search-mcp'
```

Expect all to reconcile Ready within 3 min.

- [ ] **Step 5: Verify namespace state**

```bash
kubectl get ns coder-workspaces -o jsonpath='{.metadata.labels}' | jq
kubectl get ns coder-system -o jsonpath='{.metadata.labels}' | jq
```

Confirm: coder-workspaces PSA=privileged; coder-system still PSA=baseline.

- [ ] **Step 6: Invoke cluster-validator agent.**

---

## Task 12: Kyverno guard test (negative test)

- [ ] **Step 1: Apply a pod with privileged:true but default SA**

```yaml
# /tmp/kyverno-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: kyverno-test-privileged-default-sa
  namespace: coder-workspaces
spec:
  containers:
    - name: test
      image: busybox:1.36
      command: ["sleep","1"]
      securityContext:
        privileged: true
```

```bash
kubectl apply -f /tmp/kyverno-test-pod.yaml
```

Expected: admission denied by Kyverno, `ClusterPolicy/restrict-privileged-to-coder-workspace-sa`.

- [ ] **Step 2: Apply same pod with `serviceAccountName: coder-workspace`**

Edit the file: add `spec.serviceAccountName: coder-workspace`.

```bash
kubectl apply -f /tmp/kyverno-test-pod.yaml
```

Expected: pod created.

- [ ] **Step 3: Clean up**

```bash
kubectl delete pod kyverno-test-privileged-default-sa -n coder-workspaces --ignore-not-found
rm /tmp/kyverno-test-pod.yaml
```

If admission gate didn't behave as expected, DO NOT commit / advance — fix the Kyverno policy and re-run Task 11 push.

---

## Task 13: NetworkPolicy connectivity tests

- [ ] **Step 1: Create an ad-hoc test workspace-labeled pod**

```yaml
# /tmp/cnp-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: cnp-test
  namespace: coder-workspaces
  labels:
    app.kubernetes.io/name: coder-workspace
spec:
  serviceAccountName: coder-workspace
  runtimeClassName: kata
  nodeSelector:
    kata.spruyt-labs/ready: "true"
  containers:
    - name: t
      image: docker.io/library/fedora:41
      command: ["sleep","300"]
      securityContext:
        privileged: true
```

```bash
kubectl apply -f /tmp/cnp-test-pod.yaml
kubectl wait -n coder-workspaces pod/cnp-test --for=condition=Ready --timeout=120s
```

- [ ] **Step 2: Test world egress**

```bash
kubectl -n coder-workspaces exec cnp-test -- sh -c 'curl -sfS -o /dev/null -w "%{http_code}\n" https://example.com'
```

Expected: `200`.

- [ ] **Step 3: Test MCP egress (kubectl-mcp)**

```bash
kubectl -n coder-workspaces exec cnp-test -- sh -c 'curl -sfS -o /dev/null -w "%{http_code}\n" http://kubectl-mcp-server.kubectl-mcp.svc.cluster.local:8000/health'
```

Expected: HTTP reply (200/404/etc. — non-zero code but not timeout).

- [ ] **Step 4: Test blocked-by-default intra-cluster target**

Pick a service workspaces should NOT reach. Example: the Ceph toolbox if present, or any service that has no CNP allowing workspace ingress. `curl` should hang and exit non-zero. (Use `timeout 5 curl ...` to bound.)

```bash
kubectl -n coder-workspaces exec cnp-test -- sh -c 'timeout 5 curl -sfS -o /dev/null -w "%{http_code}\n" http://<target>:<port>/ 2>&1 | tail -1'
```

Expected: timeout / no response.

- [ ] **Step 5: Clean up**

```bash
kubectl delete pod cnp-test -n coder-workspaces --ignore-not-found
rm /tmp/cnp-test-pod.yaml
```

If any test fails, debug the relevant CNP and fix (may require amending Task 4 CNPs).

---

## Task 14: Template rebuild and workspace restart

- [ ] **Step 1: Find the template-push Job**

```bash
kubectl -n coder-system get jobs | grep template
```

The `coder-template-sync` app uses a Flux-managed Job that recreates on template change. Confirm the latest Job ran after the push in Task 11 (check completion time vs push time).

- [ ] **Step 2: If Job didn't auto-run, trigger manually**

Per recent commit `857db1ce fix(coder): force-recreate template-push Job on template change`, the Job should recreate on main.tf change. If not:

```bash
flux reconcile kustomization coder-template-sync -n flux-system --with-source
```

- [ ] **Step 3: Restart an existing workspace**

In Coder UI (or via CLI if available): stop + start one workspace. Workspace should land in `coder-workspaces` ns with privileged=true.

- [ ] **Step 4: Verify workspace pod state**

```bash
kubectl -n coder-workspaces get pods -o wide
kubectl -n coder-workspaces get pod <workspace-pod> -o jsonpath='{.spec.runtimeClassName}'
kubectl -n coder-workspaces get pod <workspace-pod> -o jsonpath='{.spec.containers[?(@.name=="dev")].securityContext.privileged}'
```

Expected: runtimeClassName=kata, privileged=true.

---

## Task 15: Success criteria inside the workspace

- [ ] **Step 1: `podman run hello-world`**

SSH into the workspace or open a terminal via Coder UI. Run:

```bash
podman run --rm docker.io/library/hello-world
```

Expected: "Hello from Docker!" message.

- [ ] **Step 2: `./lint.sh`**

From the workspace, `cd` to the repo checkout and run:

```bash
./lint.sh
```

Expected: MegaLinter runs to completion, exits 0 or expected lint findings only.

- [ ] **Step 3: Envbuilder round-trip**

Trigger a template push or envbuilder rebuild via the existing Coder workflow (open a new template version in Coder UI, or re-run the template-sync Job). Expected: builds successfully, kaniko finishes without the previous podman EPERM failure.

- [ ] **Step 4: If any step fails**

Collect logs (`journalctl -u podman` inside the workspace, pod events, CNP deny audits via `hubble observe --verdict DROPPED --to-pod coder-workspaces/...`). Open a follow-up issue if the failure is orthogonal to the namespace split.

---

## Task 16: Close out + memory update

- [ ] **Step 1: Comment on #977**

```bash
gh issue comment 977 --repo anthony-spruyt/spruyt-labs --body "$(cat <<'EOF'
Option B landed. Workspaces now run in `coder-workspaces` ns with
PSA=privileged + Kyverno SA guard; `coder-system` control plane
remains PSA=baseline. Success criteria verified:

- [x] `podman run hello-world`
- [x] `./lint.sh`
- [x] envbuilder rebuild

Closing.
EOF
)"
gh issue close 977 --repo anthony-spruyt/spruyt-labs
```

- [ ] **Step 2: Update memory**

- Update `project_kata_pilot_status.md`: note Option C abandoned, Option B landed, reason.
- Remove stale probe-1 / kata-qemu references from memory if any.
- Add `feedback_kata_vm_boundary.md` capturing the decision rationale: PSA=privileged inside Kata VM is how the industry sandboxes run.

- [ ] **Step 3: Delete old workspace PVCs in `coder-system` (optional, after grace period)**

```bash
kubectl -n coder-system get pvc | grep -E 'workspaces|home'
# After confirming no running workspaces depend on them:
kubectl -n coder-system delete pvc <name>
```

Frees Ceph storage. Grace period is user's call; leave for a few days in case someone needs to extract data.

- [ ] **Step 4: Final commit**

```bash
git add docs/ .claude/ 2>/dev/null || true
git commit -m "docs(coder): close #977 with Option B landed" --allow-empty
git push
```

---

## Self-Review

**Spec coverage:**
- §1 Goal → Tasks 9, 14, 15 realise workspace move + success criteria.
- §2 Security model → Tasks 2 (PSA), 7 (Kyverno), 8 (Trivy).
- §3 Architecture (new cluster/apps/coder-workspaces tree) → Tasks 2, 3, 4, 6, 7.
- §4 NetworkPolicy design → Tasks 4 (split + relocate), 5 (MCP retarget), 13 (validation).
- §5 ExternalSecret retargets → Task 6.
- §6 Template + consumer changes → Tasks 9, 10.
- §7 Kyverno → Task 7.
- §8 Trivy → Task 8.
- §9 Validation → Tasks 11 (qa/cluster validator), 12 (Kyverno neg-test), 13 (CNP test), 15 (E2E).
- §10 Rollback → implicit (git revert); no dedicated task because no irreversible steps.
- §11 Artefacts → all paths covered in Tasks 2-10.
- §12 Open items → Task 1 covers `/dev/fuse` verification; Kyverno syntax verify in Task 7 Step 2 note; Flux dependsOn in Task 3 Step 4 note.

**Placeholder scan:** No "TBD"/"TODO" outside explicit user-action gates (SOPS edits in Task 6 Step 10 — user-driven by design per constraints).

**Type consistency:** namespace name `coder-workspaces` consistent throughout. SA name `coder-workspace` (singular) consistent with existing codebase. CNP name `allow-coder-workspace-ingress` consistent across 5 MCP files. Label `app.kubernetes.io/name: coder-workspace` consistent on pods and CNPs.
