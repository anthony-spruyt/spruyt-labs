# Coder Workspaces Namespace Split — Option B (Spec)

**Ref:** [#977](https://github.com/anthony-spruyt/spruyt-labs/issues/977)
**Date:** 2026-04-17
**Author:** brainstorm session (Claude + Anthony)
**Supersedes:** `2026-04-17-coder-podman-kata-design.md` — Option C spike abandoned after probes 3 and 4 ruled out guest kernel config and guest-side seccomp, leaving kata-agent OCI userns handling as the remaining blocker (tracked upstream `kata-containers#8170`, open since 2023).

## 1. Goal & Non-Goals

### Goal

Split Coder workspace pods into a new `coder-workspaces` namespace with PSA=privileged, keep the Coder control plane in `coder-system` at PSA=baseline, and enable privileged rootful podman inside workspace pods running under `runtimeClassName: kata`. The Kata VM remains the hard security boundary; PSA=privileged applies only to workspace pods, not control plane.

### Success criteria

1. `podman run hello-world` succeeds inside a Coder workspace pod on overlay or fuse-overlayfs storage.
2. `./lint.sh` (MegaLinter) runs to completion.
3. Envbuilder kaniko build path unaffected (template rebuild works).
4. `coder-system` namespace PSA stays at `baseline`. No relaxation.
5. Control plane pods (coder server, its CNPG Postgres) unchanged in posture.

### Non-goals

- Option A (in-place PSA relax on `coder-system`). Rejected.
- Option C probe continuation. Abandoned after probes 3+4.
- Data migration from existing workspace PVCs. Accept fresh volumes; users rebuild.
- Kata extension rollout beyond current three ms-01 workers (already complete).

## 2. Security Model

The Kata VM is the hard isolation boundary. A privileged container inside a Kata guest is equivalent to root on a dedicated microVM — the posture industry sandbox platforms (E2B, Modal, Fly Machines) ship with in production. PSA=privileged is relaxed only for the `coder-workspaces` namespace, so the Kubernetes layer still denies privileged pods everywhere else.

### Defense in depth

- **Kata VM** (hard boundary) — hypervisor-enforced memory/CPU isolation, dedicated guest kernel.
- **Namespace PSA** — `coder-workspaces` is privileged; all other namespaces including `coder-system` remain restricted or baseline.
- **Kyverno ClusterPolicy** — only ServiceAccount `coder-workspace` may create `privileged: true` pods in `coder-workspaces`. Prevents lateral privilege escalation inside the namespace if a non-workspace workload lands there by mistake.
- **NetworkPolicy default-deny** — `coder-workspaces` egress restricted to specific targets (coder-system:coder, DNS, Nexus proxy, egress gateway). No unrestricted internet.
- **Trivy posture-suppression** — `.trivyignore.yaml` allowlists privileged-related AVD findings scoped to `coder-workspaces/*` only, documented with Kata boundary rationale.

## 3. Architecture

```text
cluster/apps/
├── coder-system/                      # unchanged; PSA=baseline
│   ├── namespace.yaml                 # PSA=baseline (unchanged)
│   ├── coder/                         # Coder server + CNPG postgres (control plane)
│   └── coder-template-sync/           # retarget: provisions templates that deploy into coder-workspaces
└── coder-workspaces/                  # NEW; PSA=privileged
    ├── namespace.yaml                 # PSA enforce/audit/warn=privileged, descheduler-exclude
    ├── kustomization.yaml
    ├── workspace-rbac.yaml            # moved from coder-system; SA coder-workspace
    ├── network-policies.yaml          # new; default-deny + explicit allows (§4)
    ├── external-secrets.yaml          # retargeted ExternalSecrets (§5)
    └── kyverno-policy.yaml            # new; restricts privileged pod creation to coder-workspace SA
```

### Pod placement

- **Coder server, CNPG Postgres, template-sync Job** → `coder-system` (unchanged PSA=baseline).
- **Workspace pods** (created by Coder via Terraform on `main.tf` apply) → `coder-workspaces` (PSA=privileged, Kata runtime).

### Runtime posture of workspace pods

```yaml
spec:
  runtimeClassName: kata
  nodeSelector:
    kata.spruyt-labs/ready: "true"
  containers:
    - name: workspace
      securityContext:
        privileged: true
        runAsUser: 1000
        runAsGroup: 1000
        # capabilities: privileged implies all; PSA=privileged allows
      # /dev/fuse, /dev/net/tun exposed via privileged; verify in Kata guest
```

`startup_script` creates `/run/user/1000`, exports `XDG_RUNTIME_DIR`. Storage driver: fuse-overlayfs if `/dev/fuse` wires through; else vfs. Overlay (in-kernel) remains blocked by Kata guest whiteout restriction.

## 4. NetworkPolicy Design

Default-deny ingress + egress in `coder-workspaces`, then explicit allows.

### Egress allows

| To | Purpose |
| -- | ------- |
| `coder-system` namespace → `coder` workload, port (Coder agent registration, websocket) | Agent → server |
| `kube-system` → CoreDNS, port 53 TCP/UDP | DNS |
| `nexus-system` → `nexus` workload on HTTPS/registry ports | Docker/OCI pull-through (docker.io, quay.io, registry.k8s.io) |
| Egress gateway (existing Cilium config) → Internet | git clone, curl, package registries not behind Nexus |

### Ingress allows

| From | Purpose |
| ---- | ------- |
| `coder-system` → `coder` workload → coder-workspaces pods on agent port | Coder server → agent (SSH/port-forward/terminal) |
| (none else) | |

### Also update `coder-system` policies

Allow ingress on coder server agent ports from `coder-workspaces` namespace (ServiceAccount `coder-workspace`), reciprocal to the egress allow above.

## 5. ExternalSecret Retargets

Audit and split — do not mirror.

| ExternalSecret | Consumer | New target namespace |
| -------------- | -------- | -------------------- |
| `coder-oauth-external-secret` | Coder server | `coder-system` (unchanged) |
| `coder-workspace-env` | Workspace pods | **`coder-workspaces`** |
| `coder-talosconfig` | Workspace pods (Talos CLI access) | **`coder-workspaces`** |
| `coder-ssh-signing-key` | Workspace pods (SSH signing) | **`coder-workspaces`** |
| `coder-terraform-credentials` | Workspace pods (Terraform state) | **`coder-workspaces`** |

Retarget the `target.name` + implicit namespace (ExternalSecret lives in the target ns). No mirror-secret chains.

## 6. Template & Workspace Consumer Changes

### `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf`

- `kubernetes_deployment` / pod resource `namespace = "coder-workspaces"`.
- Reference secrets/configmaps by their new namespace.
- Add/keep `runtime_class_name = "kata"`.
- `security_context` → `privileged = true`, `run_as_user = 1000`, `run_as_group = 1000`.
- `startup_script`:
  ```bash
  sudo mkdir -p /run/user/1000
  sudo chown 1000:1000 /run/user/1000
  export XDG_RUNTIME_DIR=/run/user/1000
  ```

### `.devcontainer/post-create.sh`

- Detect Coder workspace (env var or hostname check).
- Configure podman storage (`~/.config/containers/storage.conf`): `driver = "fuse-overlayfs"` if `/dev/fuse` present, else `vfs`.
- No-op outside Coder workspace.

### `lint.sh`

- Docker-shim detection: if `/usr/bin/docker` is a podman wrapper and `sudo -n podman` works, use rootful-podman path. Removes the current EPERM failure mode.

## 7. Kyverno Policy

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-privileged-to-coder-workspace-sa
spec:
  validationFailureAction: Enforce
  rules:
    - name: only-coder-workspace-sa-privileged
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [coder-workspaces]
      preconditions:
        any:
          - key: "{{ request.object.spec.containers[?securityContext.privileged == true] | length(@) }}"
            operator: GreaterThan
            value: 0
      validate:
        message: "privileged pods in coder-workspaces require ServiceAccount 'coder-workspace'"
        pattern:
          spec:
            serviceAccountName: coder-workspace
```

Verify exact Kyverno syntax against current Kyverno version during planning.

## 8. Trivy Suppressions

`.trivyignore.yaml` additions (scoped to `coder-workspaces/**` paths only):

```yaml
- id: AVD-KSV-0017   # Privileged container
  paths:
    - "cluster/apps/coder-workspaces/**"
  comments: Kata VM boundary + Kyverno SA guard; workspace pods legitimately privileged inside microVM.
- id: AVD-KSV-0014   # readOnlyRootFilesystem
  paths:
    - "cluster/apps/coder-workspaces/**"
  comments: Workspaces need writable rootfs for package installs etc; isolation via Kata VM.
# Additional AVD IDs as they surface during `task dev-env:lint`; add one-by-one with explicit rationale.
```

## 9. Validation

### Before landing

- `task dev-env:lint` clean (with additions to `.trivyignore.yaml`).
- qa-validator agent approves each commit.

### After landing

- cluster-validator agent on each push.
- Create one workspace via Coder UI → restart → run success criteria 1-3 inside the workspace.
- `mcp__kubernetes__get_namespaces` → confirm `coder-system` PSA unchanged, `coder-workspaces` PSA=privileged.
- Kyverno: apply a test pod with `privileged: true` and a different SA in `coder-workspaces` → must be denied.
- NetworkPolicy: from a workspace pod, `curl` an unallowed internal IP → must fail; allowed IP → must succeed.

## 10. Rollback

- `git revert` the merge commit → Flux reconciles:
  - New namespace manifests removed.
  - Template-sync Job reverts to `coder-system` target → next template provision lands back in original namespace.
  - Workspace pods in-flight keep running until restart; next restart lands in reverted state.
- ExternalSecrets: revert → controller deletes secrets in `coder-workspaces` on next reconcile.
- No Talos changes in this design → no OS-level rollback.

## 11. Artefacts

| Path | Purpose |
| ---- | ------- |
| `cluster/apps/coder-workspaces/namespace.yaml` | PSA=privileged, descheduler-exclude |
| `cluster/apps/coder-workspaces/kustomization.yaml` | references namespace + sub-ks |
| `cluster/apps/coder-workspaces/workspace-rbac.yaml` | SA + Role + RoleBinding, moved from coder-system |
| `cluster/apps/coder-workspaces/network-policies.yaml` | default-deny + explicit allows per §4 |
| `cluster/apps/coder-workspaces/external-secrets.yaml` | four retargeted ExternalSecrets |
| `cluster/apps/coder-workspaces/kyverno-policy.yaml` | §7 ClusterPolicy |
| `cluster/apps/coder-system/namespace.yaml` | unchanged |
| `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf` | §6 edits |
| `cluster/apps/coder-system/network-policies.yaml` (if exists) | add ingress-from-coder-workspaces allow |
| `cluster/apps/coder-system/kustomization.yaml` | remove moved files |
| `cluster/flux/main/apps.yaml` or equivalent | register `coder-workspaces` Kustomization + dependsOn ordering |
| `.trivyignore.yaml` | §8 entries |
| `.devcontainer/post-create.sh` | §6 podman detection |
| `lint.sh` | §6 docker-shim detection |
| `docs/superpowers/specs/2026-04-17-coder-workspaces-namespace-split-design.md` | this spec |

## 12. Open Items

- Exact Kyverno CEL/JMESPath syntax against installed Kyverno version (verify during planning).
- Whether `/dev/fuse` wires through Kata guest under `privileged: true` without explicit `io.katacontainers.config.runtime.enable_fuse` or device annotation. **Verify in a throwaway test pod before full template commit.** If not, add the annotation path or fall back to vfs storage.
- Whether existing workspace PVCs in `coder-system` should be deleted after fresh volumes prove out, or retained for a grace period.
- Flux Kustomization dependsOn chain between `coder-system` and `coder-workspaces` — both must be installed; template-sync depends on both to resolve cross-ns references during template rendering.

## Appendix — Evidence Summary from Option C Probes

- Probe 0 (baseline, commit `f4d9ae43`): `rc=1` — kernel-level EPERM on multi-line `/proc/self/uid_map` write inside Kata guest. Confirmed reproducer.
- Probe 3 (OCI `kernel_params`, commit `c4e5e048`): Annotation accepted, guest cmdline included params, `CONFIG_USER_NS=y`, `max_user_namespaces=7943`, EPERM persists. **Guest kernel is NOT the blocker.**
- Probe 4 (`disable_guest_seccomp` annotation, commit `322ff1de`): Annotation accepted, `/proc/1/status` `Seccomp: 0` confirmed, EPERM persists. **Guest-side seccomp is NOT the blocker.**
- Remaining suspect: kata-agent OCI runtime userns handling. Upstream `kata-containers#8170` open since 2023, blocked on virtio-fs idmap support. Out of reach for this project.
