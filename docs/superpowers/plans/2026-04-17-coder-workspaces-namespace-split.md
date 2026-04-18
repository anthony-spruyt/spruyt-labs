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
| `cluster/apps/coder-workspaces/secrets/ks.yaml` | Flux Kustomization (with SOPS decryption block). |
| `cluster/apps/coder-workspaces/secrets/app/kustomization.yaml` | |
| `cluster/apps/coder-workspaces/secrets/app/coder-workspace-env.sops.yaml` | Moved plain SOPS Secret. |
| `cluster/apps/coder-workspaces/secrets/app/coder-talosconfig.sops.yaml` | Moved. |
| `cluster/apps/coder-workspaces/secrets/app/coder-ssh-signing-key.sops.yaml` | Moved. |
| `cluster/apps/coder-workspaces/secrets/app/coder-terraform-credentials.sops.yaml` | Moved. |
| `cluster/apps/coder-workspaces/ssh-key-rotation/**` | Full subtree relocated from coder-system (Task 6b). |
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

- [x] **Step 4: Decision gate (RESOLVED 2026-04-17)**

Probe results on Kata guest kernel 6.18.5:

- `/dev/fuse` — **absent** (mknod works in privileged container, but not provisioned by Kata devtmpfs).
- `/dev/net/tun` — absent.
- `fuse-overlayfs` — fails (`fuse: device not found`).
- `/proc/filesystems` — lists both `fuse` and `overlay` (modules available).
- Native overlay on container rootfs (virtiofs) — fails (upper fs missing `RENAME_WHITEOUT`/xattr/tmpfile).
- Native overlay on ext4 PVC — **viable** (Ceph RBD ext4 supports all required features).

**Decision: Option D' — native kernel overlay with podman storage root on workspace PVC (`$HOME`).**

Rationale: most secure (no fuse stack, no userspace FS daemon, kernel overlayfs is upstream/audited), fastest (kernel-path vs userspace), and aligns with existing workspace PVC at `$HOME`. Kata VM remains the isolation boundary. Rootful podman inside the VM is acceptable — VM, not container, is the perimeter.

Downstream adjustments (Task 10 Step 2):

- `storage.conf` `driver = "overlay"` unconditionally when in Coder workspace.
- Drop the `/dev/fuse` probe branch in `post-create.sh`.
- `graphroot` stays on `${HOME}/.local/share/containers/storage` (PVC-backed ext4 → overlay upper fs supports required features).

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
  - ./secrets/ks.yaml
  - ./kyverno-policy/ks.yaml
  - ./ssh-key-rotation/ks.yaml
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

Add `coder-workspaces` as a sibling entry on each match. Expected: 6 insertions (one per plugin with a `namespaces.exclude` list).

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

> **Cross-check pattern first — `dependsOn` is fabricated:**
> `cluster-apps-coder-workspaces` in the template above is a
> placeholder; no such Flux Kustomization exists. Before writing
> Step 4 (and reusing this pattern in Tasks 4, 6, 6b, 7):
>
> 1. Read `cluster/apps/coder-system/coder/ks.yaml` to see how the
>    existing apps handle `dependsOn` (likely none, relying on
>    parent-ks resource ordering).
> 2. Read `cluster/flux/` (look for the top-level Flux Kustomization
>    that applies `cluster/apps/`) to confirm how the namespace + its
>    children get ordered.
> 3. If the pattern is "no `dependsOn` at ks.yaml level, rely on
>    parent kustomization ordering" — drop the `dependsOn` block
>    entirely from all ks.yaml templates in this plan. Otherwise,
>    substitute the correct dependency name(s) once, and propagate.

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

Copy the 12 workspace CNPs verbatim from the source. For `allow-workspace-wireguard-tunnel`, keep its peer ns (`k8s:io.kubernetes.pod.namespace: coder-system`) unchanged — the peer `coder` server stays in `coder-system`.

Add a header comment:

```yaml
# Workspace pod CNPs for coder-workspaces namespace.
# Relocated from cluster/apps/coder-system/coder/app/network-policies.yaml.
# Pods in this ns carry label app.kubernetes.io/name: coder-workspace.
# DNS egress handled by CiliumClusterwideNetworkPolicy/allow-kube-dns-egress.
```

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

Delete the 12 CNPs whose `endpointSelector.matchLabels` is `app.kubernetes.io/name: coder-workspace` (the ones that moved in Step 2).

Then edit `allow-wireguard-tunnel` (which STAYS — its `endpointSelector` is `coder`, not `coder-workspace`): update both `egress.toEndpoints` and `ingress.fromEndpoints` `k8s:io.kubernetes.pod.namespace` from `coder-system` to `coder-workspaces`. This is the coder-server-side policy allowing tunnel traffic to/from workspace pods now living in the new namespace.

> **Transposition risk:** do NOT touch `allow-workspace-wireguard-tunnel` (different name, already moved in Step 2). Only `allow-wireguard-tunnel` (coder-server side) gets the peer-ns edit here.

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
- `cluster/apps/n8n-system/n8n/app/network-policies.yaml`

Each file has an `allow-coder-workspace-ingress` CNP with hardcoded `k8s:io.kubernetes.pod.namespace: coder-system`. Retarget to `coder-workspaces`.

- [ ] **Step 1: Audit for any other CNPs referencing coder-workspace**

```bash
grep -rln 'app.kubernetes.io/name: coder-workspace' cluster/apps/ \
  | grep network-polic
```

Expected: the 6 files above plus the coder-system file already modified in Task 4. If more appear, add them here.

- [ ] **Step 2: For each of the 6 files, edit the `allow-coder-workspace-ingress` CNP**

Change `k8s:io.kubernetes.pod.namespace: coder-system` → `k8s:io.kubernetes.pod.namespace: coder-workspaces` on the `fromEndpoints.matchLabels` line.

Leave every other CNP (Traefik ingress, kube-api egress, claude-agents ingress, etc.) untouched.

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml \
        cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml \
        cluster/apps/github-mcp/github-mcp-server/app/network-policies.yaml \
        cluster/apps/discord-mcp/discord-mcp/app/network-policies.yaml \
        cluster/apps/brave-search-mcp/brave-search-mcp/app/network-policies.yaml \
        cluster/apps/n8n-system/n8n/app/network-policies.yaml
git commit -m "refactor(mcp): retarget coder-workspace ingress to coder-workspaces ns

Ref #977"
```

---

## Task 6: Move workspace-scoped SOPS Secrets

**Note:** These are plain SOPS-encrypted `kind: Secret` resources (Flux decrypts at apply time), NOT ExternalSecrets. No SecretStore mirroring required. User has already performed the `metadata.namespace: coder-system` → `coder-workspaces` edit in the encrypted files before this task runs — do not re-edit.

**Files:**
- Create: `cluster/apps/coder-workspaces/secrets/ks.yaml`
- Create: `cluster/apps/coder-workspaces/secrets/app/kustomization.yaml`
- Move: `coder-system/coder/app/coder-workspace-env.sops.yaml` → new path
- Move: `coder-system/coder/app/coder-talosconfig.sops.yaml` → new path
- Move: `coder-system/coder/app/coder-ssh-signing-key.sops.yaml` → new path
- Move: `coder-system/coder/app/coder-terraform-credentials.sops.yaml` → new path
- Modify: `coder-system/coder/app/kustomization.yaml`

- [ ] **Step 1: Git-move each SOPS file (content preserved, no decrypt)**

```bash
mkdir -p cluster/apps/coder-workspaces/secrets/app
git mv cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml \
       cluster/apps/coder-workspaces/secrets/app/coder-workspace-env.sops.yaml
git mv cluster/apps/coder-system/coder/app/coder-talosconfig.sops.yaml \
       cluster/apps/coder-workspaces/secrets/app/coder-talosconfig.sops.yaml
git mv cluster/apps/coder-system/coder/app/coder-ssh-signing-key.sops.yaml \
       cluster/apps/coder-workspaces/secrets/app/coder-ssh-signing-key.sops.yaml
git mv cluster/apps/coder-system/coder/app/coder-terraform-credentials.sops.yaml \
       cluster/apps/coder-workspaces/secrets/app/coder-terraform-credentials.sops.yaml
```

> **Do NOT edit the SOPS ciphertext or decrypt.** The files stay
> encrypted. SOPS rules in `.sops.yaml` already match
> `cluster/apps/**` — the new path remains encrypted without further
> config. User-driven `metadata.namespace` edits were completed
> before this task.

- [ ] **Step 2: Write `secrets/app/kustomization.yaml`**

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
```

- [ ] **Step 3: Write `secrets/ks.yaml`**

Mirror pattern from Task 3's ks.yaml. Name: `coder-workspaces-secrets`. Critically — ensure SOPS decryption is configured on this Flux Kustomization (the existing coder-system Flux ks uses `spec.decryption.provider: sops` + `secretRef.name`). Copy that block verbatim from `cluster/apps/coder-system/coder/ks.yaml`.

- [ ] **Step 4: Remove moved files from `coder-system/coder/app/kustomization.yaml`**

Delete the four `- ./coder-*.sops.yaml` lines that correspond to moved files. Leave `coder-oauth-external-secret.yaml`, `coder-cnpg-credentials.sops.yaml`, etc. — those stay.

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/coder-workspaces/secrets/ \
        cluster/apps/coder-system/coder/app/kustomization.yaml
git commit -m "refactor(coder): move workspace SOPS Secrets to coder-workspaces ns

Ref #977"
```

---

## Task 6b: Relocate ssh-key-rotation app

The `ssh-key-rotation` CronJob patches the `coder-ssh-signing-key` Secret (moved in Task 6). Colocate the rotator with its target secret.

**Files (move entire subtree):**

- Move: `cluster/apps/coder-system/ssh-key-rotation/` → `cluster/apps/coder-workspaces/ssh-key-rotation/`
  - `ks.yaml`
  - `app/cronjob.yaml`
  - `app/role.yaml`
  - `app/role-binding.yaml`
  - `app/service-account.yaml`
  - `app/network-policy.yaml`
  - `app/kustomization.yaml`
  - `app/coder-ssh-rotation-token.sops.yaml` — user has already edited `metadata.namespace` to `coder-workspaces`.
- Modify: `cluster/apps/coder-system/kustomization.yaml` (drop `./ssh-key-rotation/ks.yaml`).
- Modify: `cluster/apps/coder-workspaces/kustomization.yaml` (add `./ssh-key-rotation/ks.yaml`).
- Modify: `cluster/apps/coder-workspaces/ssh-key-rotation/app/cronjob.yaml` — update `metadata.namespace: coder-system` → `coder-workspaces`.
- Modify: `cluster/apps/coder-workspaces/ssh-key-rotation/app/role.yaml` + `role-binding.yaml` + `service-account.yaml` + `network-policy.yaml` — update `metadata.namespace` (or `subjects[].namespace` in role-binding) to `coder-workspaces`.
- Modify: `cluster/apps/coder-workspaces/ssh-key-rotation/ks.yaml` — update `spec.targetNamespace: coder-system` → `coder-workspaces`. Verify `dependsOn` still resolves (may need to swap dependency from coder's Flux ks to `coder-workspaces-secrets` since the patched Secret is now there).

- [ ] **Step 1: `git mv` the entire subtree**

```bash
git mv cluster/apps/coder-system/ssh-key-rotation \
       cluster/apps/coder-workspaces/ssh-key-rotation
```

- [ ] **Step 2: Update hardcoded namespace in plaintext manifests**

```bash
grep -rln 'namespace: coder-system' cluster/apps/coder-workspaces/ssh-key-rotation/
```

For each hit, change to `coder-workspaces`. Expected files: `cronjob.yaml`, `role.yaml`, `role-binding.yaml` (both Role metadata.namespace AND `subjects[].namespace` if present), `service-account.yaml`, `network-policy.yaml`.

Leave the ClusterRoleBinding-style references alone (there aren't any in this app — only namespace-scoped Role+RoleBinding).

- [ ] **Step 3: Update `ks.yaml`**

`spec.targetNamespace: coder-system` → `coder-workspaces`. Update `dependsOn` to reference `coder-workspaces-secrets` instead of the coder Flux ks (the CronJob's dependency is the Secret it patches, which is now in `coder-workspaces`).

- [ ] **Step 4: Update parent kustomizations**

- Remove `./ssh-key-rotation/ks.yaml` from `cluster/apps/coder-system/kustomization.yaml`.
- Add `./ssh-key-rotation/ks.yaml` to `cluster/apps/coder-workspaces/kustomization.yaml`.

- [ ] **Step 5: Update README header**

`cluster/apps/coder-workspaces/ssh-key-rotation/README.md`: update namespace references in the "Operation" commands section (all `kubectl -n coder-system` → `kubectl -n coder-workspaces`; `flux reconcile kustomization` name may also change per Step 3).

- [ ] **Step 6: Commit**

```bash
git add cluster/apps/coder-system/kustomization.yaml \
        cluster/apps/coder-workspaces/
git commit -m "refactor(coder): relocate ssh-key-rotation to coder-workspaces

Rotator colocated with the coder-ssh-signing-key Secret it patches.

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

- [ ] **Step 2: Write the policy (pattern-style, pinned)**

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
          - key: "{{ request.object.spec.containers[?securityContext.privileged == `true`] | length(@) }}"
            operator: GreaterThan
            value: 0
      validate:
        message: "Privileged pods in coder-workspaces require ServiceAccount 'coder-workspace'"
        pattern:
          spec:
            serviceAccountName: coder-workspace
```

> **Verify against installed Kyverno version** before commit: `mcp__kubectl__get_deployments` (ns=kyverno) → note image tag. Kyverno ≥1.10 supports the pattern form above. If version is older, consult upstream docs for the correct precondition shape, adjust, re-validate via `kubectl apply --dry-run=server -f <file>`.

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

- [ ] **Step 2: Flip privileged + drop seccomp_profile block**

At `main.tf:449`, the current value is `privileged = false`. Flip to `true`. Also remove the `seccomp_profile { type = "RuntimeDefault" }` block at lines 452-454 — privileged pods bypass it and keeping the block adds noise.

Target:

```terraform
security_context {
  privileged                 = true
  allow_privilege_escalation = true
  read_only_root_filesystem  = false
}
```

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

- [ ] **Step 2: post-create.sh — podman storage config**

Per Task 1 Step 4 decision (Option D'): native kernel overlay on PVC-backed `$HOME`. No fuse, no `/dev/fuse`, no userspace FS daemon.

Add near the top (after initial setup, before any podman calls), guarded by Coder detection:

```bash
if [ -n "${CODER_WORKSPACE_ID:-}" ]; then
  mkdir -p ~/.config/containers
  cat > ~/.config/containers/storage.conf <<EOF
[storage]
driver = "overlay"
runroot = "/run/user/$(id -u)/containers"
graphroot = "${HOME}/.local/share/containers/storage"
EOF
fi
```

`graphroot` on workspace PVC (ext4, Ceph RBD) supports `RENAME_WHITEOUT`/xattr/tmpfile — kernel overlayfs upper-fs requirements met. Container rootfs (virtiofs) does not, so graphroot MUST stay under `$HOME`.

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

- [ ] **Step 2b: Record pre-push SHA for rollback**

```bash
git rev-parse origin/main > /tmp/coder-b-pre-push-sha
cat /tmp/coder-b-pre-push-sha
```

Save the output. Rollback procedure at end of plan uses this SHA.

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

- [ ] **Step 6: Verify SOPS decryption materialised the 5 secrets**

```bash
kubectl -n coder-workspaces get secret | grep -E \
  'coder-workspace-env|coder-talosconfig|coder-ssh-signing-key|coder-terraform-credentials|coder-ssh-rotation-token'
```

Expect 5 rows; each with DATA column > 0 (number of secret keys). If any missing → Flux SOPS decryption failed. Most likely cause: `spec.decryption` block missing on `secrets/ks.yaml` or `ssh-key-rotation/ks.yaml` (Task 6 Step 3 / Task 6b Step 3). Fix, push, reconcile before proceeding.

- [ ] **Step 7: Invoke cluster-validator agent.**

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

Collect logs (`podman logs --latest` inside the workspace, pod events, CNP deny audits via `hubble observe --verdict DROPPED --to-pod coder-workspaces/...`). Open a follow-up issue if the failure is orthogonal to the namespace split.

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

- [ ] **Step 3: Delete old workspace PVCs in `coder-system` (after grace period)**

```bash
kubectl -n coder-system get pvc | grep -E 'workspaces|home'
# After confirming no running workspaces depend on them:
kubectl -n coder-system delete pvc <name>
```

Frees Ceph storage. Grace period is user's call; leave for a few days if anyone needs to extract data.

- [ ] **Step 4: Delete probe `hack/` folders**

The Option C probe harness and the Task 1 `/dev/fuse` probe served their research purpose. Commits `4f7ad816`, `6108e579`, `f4d9ae43`, `c4e5e048`, `322ff1de`, and the Task 1 commit preserve the evidence for future reference.

```bash
git rm -r hack/kata-podman-probes hack/kata-fuse-probe
git commit -m "chore(coder): remove #977 spike probe harnesses

Evidence retained in git history (commits f4d9ae43, c4e5e048,
322ff1de, plus Task 1 fuse probe). Closing #977.

Ref #977"
git push
```

- [ ] **Step 5: Final push if any docs/ or memory edits are still local**

```bash
git status
# If anything under docs/ or .claude/ needs committing, add explicitly (no -A) and commit with a scoped message.
git push
```

---

## Rollback Appendix (if any stage causes unrecoverable state)

The plan pushes once at Task 11 Step 3. Before that push, Task 11 Step 2b records the pre-push SHA to `/tmp/coder-b-pre-push-sha`.

**Option R1 — revert commit range (preferred)**

```bash
PRE_PUSH_SHA=$(cat /tmp/coder-b-pre-push-sha)
git revert --no-commit "${PRE_PUSH_SHA}..HEAD"
git commit -m "revert: undo #977 Option B namespace split"
git push
```

`git revert` inverts each commit cleanly: `git mv` pairs re-introduce the old paths, plaintext edits invert, SOPS file edits invert by restoring the pre-edit encrypted blob. Flux reconciles back to baseline.

**Option R2 — restore from pre-push SHA (if revert conflicts)**

If a revert range produces conflicts, hard-reset a local branch to `${PRE_PUSH_SHA}` and force-push. **Requires explicit user authorisation per `.claude/rules/01-constraints.md` — force push to `main` is destructive.** DO NOT proceed without the user confirming.

**After rollback**

```bash
flux reconcile kustomization cluster-apps -n flux-system --with-source
kubectl get ns coder-workspaces  # absent or Terminating
kubectl -n coder-system get secret | grep -E \
  'coder-workspace-env|coder-talosconfig|coder-ssh-signing-key|coder-terraform-credentials|coder-ssh-rotation-token'
# all 5 secrets present again
```

---

## Self-Review

**Spec coverage:**
- §1 Goal → Tasks 9, 14, 15 realise workspace move + success criteria.
- §2 Security model → Tasks 2 (PSA), 7 (Kyverno), 8 (Trivy).
- §3 Architecture (new cluster/apps/coder-workspaces tree) → Tasks 2, 3, 4, 6, 7.
- §4 NetworkPolicy design → Tasks 4 (split + relocate), 5 (MCP retarget), 13 (validation).
- §5 Secret retargets → Task 6 (plain SOPS Secrets) + Task 6b (ssh-key-rotation relocation).
- §6 Template + consumer changes → Tasks 9, 10.
- §7 Kyverno → Task 7.
- §8 Trivy → Task 8.
- §9 Validation → Tasks 11 (qa/cluster validator), 12 (Kyverno neg-test), 13 (CNP test), 15 (E2E).
- §10 Rollback → dedicated Rollback Appendix between Tasks 16 and Self-Review; pre-push SHA captured in Task 11 Step 2b.
- §11 Artefacts → all paths covered in Tasks 2-10.
- §12 Open items → Task 1 `/dev/fuse` verification RESOLVED (Option D' native overlay on PVC, see Task 1 Step 4); Kyverno syntax verify in Task 7 Step 2 note; Flux dependsOn in Task 3 Step 4 note.

**Placeholder scan:** No "TBD"/"TODO" outside explicit user-action gates (SOPS edits in Task 6 Step 10 — user-driven by design per constraints).

**Type consistency:** namespace name `coder-workspaces` consistent throughout. SA name `coder-workspace` (singular) consistent with existing codebase. CNP name `allow-coder-workspace-ingress` consistent across 5 MCP files. Label `app.kubernetes.io/name: coder-workspace` consistent on pods and CNPs.
