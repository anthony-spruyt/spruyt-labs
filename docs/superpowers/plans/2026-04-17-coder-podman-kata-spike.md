# Coder Podman-in-Kata Research Spike — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute Option C research spike from spec `docs/superpowers/specs/2026-04-17-coder-podman-kata-design.md` — find a config-only (or minimal-escalation) fix that lets rootless podman run inside a Coder workspace pod under `runtimeClassName: kata`, without privileged or PSA relaxation.

**Architecture:** Probe-harness first, then sequential probe execution with user-approval gates between C1/C2/C3 phases. Each probe is an ephemeral `kubectl run` pod on a kata-ready worker. Results logged to dated markdown in `hack/kata-podman-probes/`. Landing artefacts are skeleton tasks — filled in once a probe passes.

**Tech Stack:** Talos Linux, Kata Containers (siderolabs extension), cloud-hypervisor, Cilium, Fedora-based probe image, `kubectl run`, `newuidmap`/`unshare` userns reproducer.

**Related:** Issue [#977](https://github.com/anthony-spruyt/spruyt-labs/issues/977). Ref #933 (Kata umbrella).

---

## File Structure

| Path | Responsibility |
| ---- | -------------- |
| `hack/kata-podman-probes/README.md` | How to run probes, repro command, result logging convention. |
| `hack/kata-podman-probes/probe.sh` | Single-entry runner: accepts `--probe N` flag, spawns pod, runs repro, prints pass/fail. |
| `hack/kata-podman-probes/manifests/` | Per-probe pod YAML (runtimeClass variants, annotations, securityContext combos). |
| `hack/kata-podman-probes/results-YYYY-MM-DD.md` | Per-run results table. Latest appended as Appendix A in the spec. |
| `docs/superpowers/specs/2026-04-17-coder-podman-kata-design.md` | Appendix A updated with results after each probe session. |
| **Landing artefacts (TBD after winning probe)** | — |
| `cluster/apps/kube-system/kata-runtimeclass/` | Possibly patch existing `kata` RuntimeClass, or add `kata-workspace` variant. |
| `talos/talconfig.yaml` | Possibly ms01 anchor sysctl or extension pin. |
| `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf` | Template updates (`runtime_class_name`, storage, XDG, securityContext). |
| `.devcontainer/post-create.sh`, `lint.sh` | Workspace-side consumer updates. |

---

## Task 1: Scaffold probe harness

**Files:**
- Create: `hack/kata-podman-probes/README.md`
- Create: `hack/kata-podman-probes/probe.sh`
- Create: `hack/kata-podman-probes/manifests/base.yaml`

- [ ] **Step 1: Write `hack/kata-podman-probes/README.md`**

````markdown
# Kata Podman Probes

Research harness for [#977](https://github.com/anthony-spruyt/spruyt-labs/issues/977).
Diagnoses why rootless podman fails inside Kata-runtime pods.

## Quickstart

```bash
./hack/kata-podman-probes/probe.sh --probe 1
```

Each probe spawns an ephemeral pod on a kata-ready worker, runs the userns reproducer,
prints pass/fail, deletes the pod.

## Reproducer

Inside the pod:

```sh
unshare -U sh -c 'newuidmap $$ 0 1000 1 1 100000 65536; echo rc=$?'
```

`rc=0` = pass (multi-line uid_map write works).
EPERM or nonzero rc = fail (current broken state).

## Probes

C1 breadth-first config sweep (run first, stop at first green):

1. Hypervisor swap (CLH → QEMU via `RuntimeClass: kata-qemu`)
2. Guest sysctls (`kernel.unprivileged_userns_clone=1` etc.)
3. Kata OCI annotations (`io.katacontainers.config.hypervisor.kernel_params=...`)
4. kata `configuration.toml` overrides (`disable_guest_seccomp=true`)
5. `procMount: Unmasked` (with and without `hostUsers: false`)
6. `allowPrivilegeEscalation: true` + non-root

C2 (confinement deep-dive) and C3 (version bisect) require explicit user approval before execution.

## Logging

Results are appended to `results-YYYY-MM-DD.md` and then merged into
`docs/superpowers/specs/2026-04-17-coder-podman-kata-design.md` Appendix A.
````

- [ ] **Step 2: Write `hack/kata-podman-probes/probe.sh`**

```bash
#!/usr/bin/env bash
# Kata podman probe harness for #977
set -euo pipefail

PROBE="${1:-}"
[[ -z "${PROBE}" ]] && { echo "usage: $0 <probe-number>" >&2; exit 2; }

MANIFEST="$(dirname "$0")/manifests/probe-${PROBE}.yaml"
[[ ! -f "${MANIFEST}" ]] && { echo "no manifest: ${MANIFEST}" >&2; exit 2; }

POD="kata-podman-probe-${PROBE}-$(date +%s)"
NS="default"

# shellcheck disable=SC2064
trap "kubectl -n ${NS} delete pod ${POD} --ignore-not-found --wait=false" EXIT

sed "s|__POD_NAME__|${POD}|g" "${MANIFEST}" | kubectl -n "${NS}" apply -f -

kubectl -n "${NS}" wait --for=condition=Ready "pod/${POD}" --timeout=120s

echo "--- probe ${PROBE} repro ---"
kubectl -n "${NS}" exec "${POD}" -- sh -c '
  dnf -qy install shadow-utils util-linux > /dev/null 2>&1 || true
  unshare -U sh -c "newuidmap \$\$ 0 1000 1 1 100000 65536; echo rc=\$?"
'
echo "--- probe ${PROBE} dmesg tail ---"
kubectl -n "${NS}" exec "${POD}" -- sh -c 'dmesg 2>/dev/null | tail -20 || echo "(dmesg unavailable)"'
```

- [ ] **Step 3: Write `hack/kata-podman-probes/manifests/base.yaml` (template used by each probe-N.yaml)**

```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: __POD_NAME__
  labels:
    app.kubernetes.io/name: kata-podman-probe
    app.kubernetes.io/component: probe-base
  annotations: {}
spec:
  runtimeClassName: kata
  restartPolicy: Never
  nodeSelector:
    kata.spruyt-labs/ready: "true"
  containers:
    - name: probe
      image: docker.io/library/fedora:latest
      imagePullPolicy: IfNotPresent
      command: ["sleep", "600"]
      securityContext:
        runAsNonRoot: false
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
          add: ["SETUID", "SETGID"]
```

- [ ] **Step 4: `chmod +x hack/kata-podman-probes/probe.sh`**

Run: `chmod +x hack/kata-podman-probes/probe.sh`

- [ ] **Step 5: Commit**

```bash
git add hack/kata-podman-probes/
git commit -m "feat(coder): add kata-podman probe harness

Ref #977"
```

---

## Task 2: Baseline probe (probe 0 — confirm current broken state)

**Files:**
- Create: `hack/kata-podman-probes/manifests/probe-0.yaml`

- [ ] **Step 1: Write baseline manifest**

```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: __POD_NAME__
  labels:
    app.kubernetes.io/name: kata-podman-probe
    app.kubernetes.io/component: probe-0-baseline
spec:
  runtimeClassName: kata
  restartPolicy: Never
  nodeSelector:
    kata.spruyt-labs/ready: "true"
  containers:
    - name: probe
      image: docker.io/library/fedora:latest
      command: ["sleep", "600"]
      securityContext:
        runAsNonRoot: false
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
          add: ["SETUID", "SETGID"]
```

- [ ] **Step 2: Run baseline**

Run: `./hack/kata-podman-probes/probe.sh 0`
Expected: `rc=1` (EPERM) — confirms the broken state reproduces reliably. If `rc=0`, diagnosis is wrong; STOP and re-triage.

- [ ] **Step 3: Log baseline**

Create `hack/kata-podman-probes/results-$(date +%Y-%m-%d).md`:

```markdown
# Kata Podman Probe Results — YYYY-MM-DD

| # | Probe | rc | Notes |
|---|-------|----|----|
| 0 | baseline | 1 | EPERM as expected; diagnosis reproduces |
```

- [ ] **Step 4: Commit**

```bash
git add hack/kata-podman-probes/
git commit -m "test(coder): confirm kata podman baseline broken state

Ref #977"
```

---

## Task 3: Probe 1 — hypervisor swap (CLH → QEMU)

**Files:**
- Create: `cluster/apps/kube-system/kata-runtimeclass/kata-qemu.yaml` (additive RuntimeClass, not replacing existing `kata`)
- Create: `hack/kata-podman-probes/manifests/probe-1.yaml`

**Context:** Current `kata` RuntimeClass handler is `kata` which maps to the CLH hypervisor on Talos `siderolabs/kata-containers` extension. The extension also ships a `kata-qemu` handler. Adding a second RuntimeClass that references `kata-qemu` lets this probe swap hypervisor without disturbing existing workloads.

- [ ] **Step 1: Inspect existing kata RuntimeClass**

Run: `mcp__kubernetes__get_custom_resource` with `kind=RuntimeClass name=kata` (or `kubectl get runtimeclass kata -o yaml` as fallback).
Record the `handler:` value. Confirm `kata-qemu` handler is available on the node: `talosctl -n <ms01-ip> read /etc/kata-containers/` (if permitted) OR inspect Talos extension docs.

- [ ] **Step 2: Create `cluster/apps/kube-system/kata-runtimeclass/kata-qemu.yaml`**

```yaml
---
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-qemu
handler: kata-qemu
scheduling:
  nodeSelector:
    kata.spruyt-labs/ready: "true"
```

- [ ] **Step 3: Add to kustomization**

Modify `cluster/apps/kube-system/kata-runtimeclass/kustomization.yaml`: append `- kata-qemu.yaml` to `resources:`.

- [ ] **Step 4: qa-validator, commit, push**

```bash
git add cluster/apps/kube-system/kata-runtimeclass/
git commit -m "feat(kata): add kata-qemu RuntimeClass for probe testing

Additive; existing kata (CLH) unchanged. Used by #977 probe harness.

Ref #977"
git push
```

Wait for Flux reconcile (~30s via webhook).

- [ ] **Step 5: Write `hack/kata-podman-probes/manifests/probe-1.yaml`**

Identical to probe-0.yaml but with `runtimeClassName: kata-qemu`.

```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: __POD_NAME__
  labels:
    app.kubernetes.io/name: kata-podman-probe
    app.kubernetes.io/component: probe-1-qemu
spec:
  runtimeClassName: kata-qemu
  restartPolicy: Never
  nodeSelector:
    kata.spruyt-labs/ready: "true"
  containers:
    - name: probe
      image: docker.io/library/fedora:latest
      command: ["sleep", "600"]
      securityContext:
        runAsNonRoot: false
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
          add: ["SETUID", "SETGID"]
```

- [ ] **Step 6: Run probe 1**

Run: `./hack/kata-podman-probes/probe.sh 1`

- [ ] **Step 7: Log result**

Append to `results-YYYY-MM-DD.md`:

```markdown
| 1 | hypervisor=qemu | <rc> | <observations> |
```

- [ ] **Step 8: Decision gate**

- If `rc=0`: STOP probing. Skip to Task 16 (landing) with winner = hypervisor swap.
- If `rc!=0`: commit probe artefacts, proceed to Task 4.

- [ ] **Step 9: Commit probe artefacts**

```bash
git add hack/kata-podman-probes/
git commit -m "test(coder): probe 1 hypervisor swap result

Ref #977"
```

---

## Task 4: Probe 2 — guest sysctls

**Files:**
- Create: `hack/kata-podman-probes/manifests/probe-2.yaml`

**Context:** Set userns-related sysctls inside the pod at startup. Requires `initContainers` with `securityContext.privileged: true`? No — PSA baseline forbids. Instead, rely on pod `spec.securityContext.sysctls` (unsafe-sysctls may require kubelet allowlist). Three sysctls to try in one probe; if any flips behavior we'll narrow.

- [ ] **Step 1: Write manifest**

```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: __POD_NAME__
  labels:
    app.kubernetes.io/name: kata-podman-probe
    app.kubernetes.io/component: probe-2-sysctls
spec:
  runtimeClassName: kata
  restartPolicy: Never
  nodeSelector:
    kata.spruyt-labs/ready: "true"
  securityContext:
    sysctls:
      - name: kernel.unprivileged_userns_clone
        value: "1"
      - name: user.max_user_namespaces
        value: "15000"
  containers:
    - name: probe
      image: docker.io/library/fedora:latest
      command: ["sleep", "600"]
      securityContext:
        runAsNonRoot: false
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
          add: ["SETUID", "SETGID"]
```

- [ ] **Step 2: Run probe 2**

Run: `./hack/kata-podman-probes/probe.sh 2`

If pod refuses to schedule due to unsafe-sysctl: kubelet doesn't allow those sysctls in Kata guest. Note this in results and fall back to running `sysctl -w` inside the pod via the repro script (requires CAP_SYS_ADMIN — add temporarily for this probe only if needed):

Alt inline approach (edit `probe-2.yaml` to add `SYS_ADMIN` cap):

```yaml
      capabilities:
        drop: ["ALL"]
        add: ["SETUID", "SETGID", "SYS_ADMIN"]
```

Then repro: `sysctl -w kernel.unprivileged_userns_clone=1 user.max_user_namespaces=15000; unshare -U ...`

- [ ] **Step 3: Log, decide, commit**

- `rc=0` → STOP, winner = sysctl. Jump to Task 16.
- `rc!=0` → log and proceed.

```bash
git add hack/kata-podman-probes/
git commit -m "test(coder): probe 2 sysctls result

Ref #977"
```

---

## Task 5: Probe 3 — kata OCI annotations

**Files:**
- Create: `hack/kata-podman-probes/manifests/probe-3.yaml`

**Context:** Kata reads `io.katacontainers.config.*` pod annotations to override guest kernel params per-pod. Requires the relevant annotations to be whitelisted in kata's `configuration.toml` (`enable_annotations` list). Probe will fail fast with kata-runtime error if annotation is not whitelisted — that's a signal we need Task 6 route.

- [ ] **Step 1: Write manifest**

```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: __POD_NAME__
  labels:
    app.kubernetes.io/name: kata-podman-probe
    app.kubernetes.io/component: probe-3-annotations
  annotations:
    io.katacontainers.config.hypervisor.kernel_params: "user_namespace.enable=1 userns.max=15000"
spec:
  runtimeClassName: kata
  restartPolicy: Never
  nodeSelector:
    kata.spruyt-labs/ready: "true"
  containers:
    - name: probe
      image: docker.io/library/fedora:latest
      command: ["sleep", "600"]
      securityContext:
        runAsNonRoot: false
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
          add: ["SETUID", "SETGID"]
```

- [ ] **Step 2: Run, observe kata-agent event**

Run: `./hack/kata-podman-probes/probe.sh 3`

If pod fails with `annotation not whitelisted`: record this — fix requires patching Talos kata config (escalate to Task 6 or flag for Q3 option (c)).

- [ ] **Step 3: Log, decide, commit**

- `rc=0` → STOP, winner = OCI annotation. Task 16.
- Annotation rejected → note, proceed to Task 6.
- `rc!=0` otherwise → proceed.

```bash
git add hack/kata-podman-probes/
git commit -m "test(coder): probe 3 OCI annotations result

Ref #977"
```

---

## Task 6: Probe 4 — kata configuration.toml override (disable_guest_seccomp)

**Files:**
- Modify (temporarily): Talos machine config via `talos/talconfig.yaml` patch OR RuntimeClass with custom handler.

**Context:** `disable_guest_seccomp=true` would rule out kata-agent seccomp as the blocker. Requires editing kata `configuration.toml` inside the Talos kata extension. Two deployment routes:

- (preferred) Introduce a new kata handler `kata-no-seccomp` referenced by a new RuntimeClass. Implementation depends on whether `siderolabs/kata-containers` exposes per-handler config files.
- (fallback) Patch the default kata config via Talos `machine.files` (write `/etc/kata-containers/configuration-overlay.toml`).

- [ ] **Step 1: Inspect available kata handlers on ms-01-3**

Run: `talosctl -n <ms01-3-ip> ls /opt/kata-containers/share/defaults/kata-containers/` (path varies — adjust per Talos extension layout).
Record paths to `configuration*.toml` files.

- [ ] **Step 2: Decide route**

If per-handler TOML is overridable: create a machine-config patch adding a new config file at a separate path + a RuntimeClass `kata-no-seccomp` referencing a new handler. If not: flag as "requires kata extension fork" and proceed to Task 7 (do not run this probe; escalate to user).

- [ ] **Step 3: Apply chosen route**

*Skeleton — fill once Step 1 output known. Follow `feedback_talos_genconfig.md`: regenerate configs via `task talos:gen`, apply with `task talos:apply-w1/w2/w3`. No `talos-upgrade` agent needed unless extension itself changes.*

- [ ] **Step 4: Create `hack/kata-podman-probes/manifests/probe-4.yaml`**

```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: __POD_NAME__
  labels:
    app.kubernetes.io/name: kata-podman-probe
    app.kubernetes.io/component: probe-4-no-seccomp
spec:
  runtimeClassName: kata-no-seccomp
  restartPolicy: Never
  nodeSelector:
    kata.spruyt-labs/ready: "true"
  containers:
    - name: probe
      image: docker.io/library/fedora:latest
      command: ["sleep", "600"]
      securityContext:
        runAsNonRoot: false
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
          add: ["SETUID", "SETGID"]
```

- [ ] **Step 5: Run, log, decide, commit**

```bash
./hack/kata-podman-probes/probe.sh 4
```

- `rc=0` → STOP, winner = disable guest seccomp. Task 16.
- Otherwise → note, proceed to Task 7. Remove the temporary no-seccomp RuntimeClass via `git revert` of the Talos patch commit before moving on (seccomp disabled is not an acceptable long-term state even in probe mode).

```bash
git add hack/kata-podman-probes/ talos/
git commit -m "test(coder): probe 4 disable_guest_seccomp result

Ref #977"
```

---

## Task 7: Probe 5 — procMount Unmasked combos

**Files:**
- Create: `hack/kata-podman-probes/manifests/probe-5a.yaml` (procMount only)
- Create: `hack/kata-podman-probes/manifests/probe-5b.yaml` (procMount + hostUsers:false)

**Context:** PSA baseline forbids `procMount: Unmasked` by default. Both probe variants will require a short-lived namespace PSA relaxation on `default` (not `coder-system`). Revert PSA label immediately after probe.

- [ ] **Step 1: Temporarily relax default ns PSA**

```bash
kubectl label --overwrite ns default \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/warn=privileged
```

- [ ] **Step 2: Write probe-5a.yaml (procMount: Unmasked, hostUsers default)**

```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: __POD_NAME__
  labels:
    app.kubernetes.io/name: kata-podman-probe
    app.kubernetes.io/component: probe-5a-procmount
spec:
  runtimeClassName: kata
  restartPolicy: Never
  nodeSelector:
    kata.spruyt-labs/ready: "true"
  containers:
    - name: probe
      image: docker.io/library/fedora:latest
      command: ["sleep", "600"]
      securityContext:
        procMount: Unmasked
        runAsNonRoot: false
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
          add: ["SETUID", "SETGID"]
```

- [ ] **Step 3: Write probe-5b.yaml (procMount + hostUsers:false)**

Same as 5a plus `spec.hostUsers: false`.

- [ ] **Step 4: Run both**

```bash
./hack/kata-podman-probes/probe.sh 5a
./hack/kata-podman-probes/probe.sh 5b
```

- [ ] **Step 5: RESTORE default ns PSA immediately**

```bash
kubectl label --overwrite ns default \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=baseline
```

Verify: `mcp__kubernetes__get_namespaces` — `default` labels show `baseline`.

- [ ] **Step 6: Log, decide, commit**

- Either `rc=0` → winner = procMount (note which variant). Task 16.
- Both fail → proceed to Task 8.

```bash
git add hack/kata-podman-probes/
git commit -m "test(coder): probe 5 procMount Unmasked result

Ref #977"
```

---

## Task 8: Probe 6 — allowPrivilegeEscalation + setuid helper

**Files:**
- Create: `hack/kata-podman-probes/manifests/probe-6.yaml`

- [ ] **Step 1: Write manifest**

```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: __POD_NAME__
  labels:
    app.kubernetes.io/name: kata-podman-probe
    app.kubernetes.io/component: probe-6-no-nnp
spec:
  runtimeClassName: kata
  restartPolicy: Never
  nodeSelector:
    kata.spruyt-labs/ready: "true"
  containers:
    - name: probe
      image: docker.io/library/fedora:latest
      command: ["sleep", "600"]
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        allowPrivilegeEscalation: true
        capabilities:
          drop: ["ALL"]
```

- [ ] **Step 2: Run probe 6**

Run: `./hack/kata-podman-probes/probe.sh 6`

- [ ] **Step 3: Log, decide, commit**

- `rc=0` → winner = NO_NEW_PRIVS off. Task 16.
- `rc!=0` → C1 exhausted. Gate to Task 9.

```bash
git add hack/kata-podman-probes/
git commit -m "test(coder): probe 6 allowPrivilegeEscalation result

Ref #977"
```

---

## Task 9: C1 decision gate (USER APPROVAL REQUIRED)

- [ ] **Step 1: Update spec Appendix A**

Merge `hack/kata-podman-probes/results-YYYY-MM-DD.md` into `docs/superpowers/specs/2026-04-17-coder-podman-kata-design.md` Appendix A.

- [ ] **Step 2: Post summary comment on issue #977**

```bash
gh issue comment 977 --repo anthony-spruyt/spruyt-labs --body "$(cat <<'EOF'
## C1 complete — all red

<paste results table>

**Request approval to proceed to C2 (guest confinement deep-dive).** See plan Task 10+.
EOF
)"
```

- [ ] **Step 3: Wait for explicit user approval before Task 10.**

If user chooses to abandon C → jump to "Plan abandoned" epilogue (re-brainstorm B). If user approves C2 → proceed.

- [ ] **Step 4: Commit spec appendix update**

```bash
git add docs/superpowers/specs/
git commit -m "docs(coder): append C1 probe results

Ref #977"
```

---

## Task 10: C2 probe — seccomp dump + dmesg + strace

**Files:**
- Create: `hack/kata-podman-probes/manifests/probe-c2.yaml` (richer toolchain: `strace`, `libseccomp-tools`)

- [ ] **Step 1: Write manifest**

```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: __POD_NAME__
  labels:
    app.kubernetes.io/name: kata-podman-probe
    app.kubernetes.io/component: probe-c2-deepdive
spec:
  runtimeClassName: kata
  restartPolicy: Never
  nodeSelector:
    kata.spruyt-labs/ready: "true"
  containers:
    - name: probe
      image: docker.io/library/fedora:latest
      command: ["sleep", "1800"]
      securityContext:
        runAsNonRoot: false
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
          add: ["SETUID", "SETGID"]
```

- [ ] **Step 2: Run probe and collect diagnostics**

```bash
./hack/kata-podman-probes/probe.sh c2
POD=$(kubectl get pod -l app.kubernetes.io/component=probe-c2-deepdive -o name | head -1)

# A: seccomp bitmap
kubectl exec "${POD}" -- grep -i seccomp /proc/1/status

# B: LSMs loaded in guest
kubectl exec "${POD}" -- sh -c 'ls /sys/kernel/security/ 2>/dev/null; cat /sys/kernel/security/lsm 2>/dev/null'

# C: dmesg during repro
kubectl exec "${POD}" -- sh -c 'dnf -qy install util-linux shadow-utils strace > /dev/null 2>&1; dmesg -c > /dev/null 2>&1 || true; unshare -U sh -c "newuidmap \$\$ 0 1000 1 1 100000 65536; echo rc=\$?"; dmesg 2>/dev/null | tail -40'

# D: strace newuidmap
kubectl exec "${POD}" -- sh -c 'unshare -U sh -c "strace -f -o /tmp/nuid.trace newuidmap \$\$ 0 1000 1 1 100000 65536; tail -30 /tmp/nuid.trace"'
```

- [ ] **Step 3: Save outputs to `hack/kata-podman-probes/c2-output-YYYY-MM-DD.md`**

Include all four blocks verbatim. Identify which syscall returns EPERM. Compare to known 6.18 kernel userns gates (`CONFIG_USER_NS`, `CONFIG_USER_NS_UNPRIVILEGED`, `deny_write_access` on uid_map).

- [ ] **Step 4: Decision**

- If strace pinpoints a specific syscall+gate addressable by config → go to Task 11 (apply that config as a new probe). If winner → Task 16.
- If root cause is "guest kernel lacks CONFIG_FOO" → escalate to Task 12 (version bisect) or flag for Q3 option (c).
- If inconclusive → flag to user for decision.

- [ ] **Step 5: Commit**

```bash
git add hack/kata-podman-probes/
git commit -m "test(coder): C2 confinement diagnostics

Ref #977"
```

---

## Task 11: C2 targeted config probe (conditional)

**Only run if Task 10 identified a specific config-addressable root cause.**

- [ ] **Step 1: Create `hack/kata-podman-probes/manifests/probe-c2-fix.yaml` with the targeted config from Task 10**

*Skeleton — fill with specific sysctl, annotation, OCI flag identified in Task 10.*

- [ ] **Step 2: Run, log, decide**

- `rc=0` → winner. Task 16.
- `rc!=0` → C2 exhausted, gate to Task 12.

- [ ] **Step 3: Commit**

```bash
git add hack/kata-podman-probes/
git commit -m "test(coder): C2 targeted fix probe

Ref #977"
```

---

## Task 12: C2→C3 decision gate (USER APPROVAL REQUIRED)

Mirror of Task 9. Update spec Appendix A, comment on #977 summarising C2 findings, wait for approval before C3.

- [ ] **Step 1: Append C2 findings to spec Appendix A**
- [ ] **Step 2: Comment on #977**
- [ ] **Step 3: Wait for user approval to proceed to C3**
- [ ] **Step 4: Commit**

---

## Task 13: C3 version bisect

**Files:**
- Modify: factory schematic for ms-01 anchor in `talos/talconfig.yaml` (one change per bisect step).

**Context:** `siderolabs/kata-containers` version pinning is handled via factory-generated schematic IDs. Each bisect step requires a new schematic + `talos-upgrade` sequence across all three workers.

- [ ] **Step 1: Enumerate siderolabs kata-containers releases**

Run: `gh release list --repo siderolabs/extensions --limit 20` (or query factory API).
Record current version + N-1, N-2, N-3 candidates.

- [ ] **Step 2: Bisect step**

For each candidate version (newest-first, binary search):

1. Edit `talos/talconfig.yaml` ms01 schematic anchor to pin extension to candidate version.
2. `task talos:gen && talhelper gencommand upgrade` (see `feedback_talos_genconfig.md`).
3. Register schematic via `curl -sX POST https://factory.talos.dev/schematics`.
4. Invoke `talos-upgrade` agent — sequential across ms-01-1/2/3 (Ceph HEALTH_OK between each).
5. Wait for all workers ready.
6. Re-run `./hack/kata-podman-probes/probe.sh 0` (baseline on current kata version).
7. Record rc. If `rc=0` → good boundary; bisect forward. If `rc=1` → bad; bisect backward.

- [ ] **Step 3: Identify good→bad version boundary**

- [ ] **Step 4: If boundary found → winner = pin to last-good version**

Proceed to Task 16 with winner = extension version pin.

- [ ] **Step 5: If no good version in reasonable window → C3 exhausted**

Gate to user: abandon C (re-brainstorm B) or escalate to custom kernel path (Q3 option c/d). No further probes in this plan.

- [ ] **Step 6: Commit after each bisect step**

```bash
git add talos/
git commit -m "test(coder): C3 bisect kata-containers <version>

Ref #977"
```

---

## Task 14: C3 decision gate (USER APPROVAL REQUIRED if abandoning)

- [ ] **Step 1: Append C3 findings to spec Appendix A**
- [ ] **Step 2: Comment on #977**
- [ ] **Step 3: If winner → Task 16. If exhausted → explicit user decision on abandon vs escalate.**

---

## Task 15: (Reserved — intentional gap)

Kept blank to preserve task numbering when tasks are reordered. Skip.

---

## Task 16: Land the winning config

**Files (depend on winner):**

| Winner | Primary files |
| ------ | ------------- |
| Hypervisor (probe 1) | `cluster/apps/kube-system/kata-runtimeclass/kata-qemu.yaml` promoted to production use; Coder template `runtime_class_name = "kata-qemu"`. |
| Sysctl (probe 2) | `talos/talconfig.yaml` ms01 anchor `machine.sysctls`; OR Coder pod `spec.securityContext.sysctls` + kubelet unsafe-sysctl allowlist (talos patch). |
| OCI annotation (probe 3) | Coder template pod `metadata.annotations` + possibly Talos kata config `enable_annotations` patch. |
| kata config / no-seccomp (probe 4) | Rejected — insecure. Only land if combined with another non-seccomp fix. |
| procMount (probe 5) | Coder template pod `securityContext.procMount: Unmasked`. Verify PSA `baseline` permits (some combinations require PSA relax — abort if so; this would invalidate non-goal constraint). |
| No-new-privs (probe 6) | Coder template pod `securityContext.allowPrivilegeEscalation: true`. PSA baseline-compatible. |
| Extension version pin (C3) | `talos/talconfig.yaml` pin + factory schematic. |

- [ ] **Step 1: Write the landing change(s) for the specific winner.**

Concrete steps depend on winner — apply the edits, using existing patterns:

- Coder template edits → follow existing `main.tf` structure; re-run template-sync Job.
- Talos patch → `task talos:gen` + `task talos:apply-w1/w2/w3` (no upgrade needed unless extension version changed).
- RuntimeClass → already shipped in Task 3 if hypervisor; otherwise create parallel `kata-workspace` RuntimeClass.

- [ ] **Step 2: Update Coder workspace consumer scripts if required**

Files: `.devcontainer/post-create.sh`, `lint.sh`. Remove any `sudo podman` shim assumptions if rootless now works; create `/run/user/1000` + export `XDG_RUNTIME_DIR` in `post-create.sh` if not already.

- [ ] **Step 3: qa-validator**

Invoke qa-validator agent before committing.

- [ ] **Step 4: Commit + push**

```bash
git add <specific files>
git commit -m "fix(coder): enable rootless podman in kata workspace

Winner: <probe name>. Closes #977."
git push
```

- [ ] **Step 5: cluster-validator**

After push, invoke cluster-validator agent.

---

## Task 17: End-to-end validation

- [ ] **Step 1: Rebuild Coder template**

Trigger template-sync Job: `kubectl -n coder-system create job --from=cronjob/coder-template-sync validate-podman-fix` (or equivalent path — inspect `cluster/apps/coder-system/coder-template-sync/` for actual trigger).

- [ ] **Step 2: Restart one workspace**

User action in Coder UI, OR `coder restart <workspace>` via CLI from host.

- [ ] **Step 3: Run success criteria inside workspace**

```bash
# Criterion 1
podman run --rm docker.io/library/hello-world

# Criterion 2
./lint.sh

# Criterion 3 (envbuilder round-trip) — rebuild via Coder template sync Job or envbuilder dev pod
```

- [ ] **Step 4: Attach results + close #977**

```bash
gh issue comment 977 --repo anthony-spruyt/spruyt-labs --body "Validated: all 3 success criteria green. Closing."
gh issue close 977 --repo anthony-spruyt/spruyt-labs
```

---

## Task 18: Post-mortem + memory update

- [ ] **Step 1: Update `project_kata_pilot_status.md` with winner + pitfalls.**

- [ ] **Step 2: Add `feedback_*.md` memory if the spike uncovered a durable lesson.**

- [ ] **Step 3: Final commit**

```bash
git add docs/ hack/
git commit -m "docs(coder): post-mortem for #977 spike"
git push
```

---

## Plan Abandoned Epilogue (conditional)

If at any decision gate the user elects to abandon C:

- [ ] Revert any probe-only Talos / RuntimeClass commits.
- [ ] Comment on #977 marking C abandoned with reasons.
- [ ] Open a fresh brainstorm session referencing spec + this plan, targeting Option B (namespace split).

---

## Self-Review

- Spec §1 goal — covered by success criteria referenced in Task 17.
- Spec §2 architecture — Tasks 1-15 implement probe phase; Task 16 implements landing phase.
- Spec §3 probe plan — Tasks 3-8 cover C1 probes 1-6; Task 10-11 C2; Task 13 C3.
- Spec §4 decision gates — Tasks 9, 12, 14 are the three gates.
- Spec §5 artefacts — hack/kata-podman-probes/ tree created in Tasks 1-2; landing artefacts enumerated in Task 16 table.
- Spec §6 rollback — Task 7 restores default ns PSA explicitly; Task 6 reverts no-seccomp; Plan-abandoned epilogue handles full rollback.
- Spec §7 testing — qa-validator + cluster-validator invoked in Task 16; E2E in Task 17.
- Spec §8 open items — landing-site decision made in Task 16; storage driver resolved during workspace validation in Task 17.

No placeholders except the deliberately conditional Tasks 6/11 skeleton fills (gated on prior probe outputs). Type consistency: `probe.sh` accepts probe number/name matching manifest filename convention `probe-N.yaml`; all probes use same repro command; `kata-qemu` handler name consistent across Tasks 3 and 16.
