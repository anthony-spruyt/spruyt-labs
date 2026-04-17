# Podman-in-Kata Prior Art Research

Date: 2026-04-17
Issue: [#977](https://github.com/anthony-spruyt/spruyt-labs/issues/977)

## Executive summary

There is **no officially supported rootless-podman-in-a-Kata-pod pattern** in 2026.
Kata Containers does not yet implement Linux user namespaces inside the guest
(tracking issue [kata-containers#8170][kata-8170] — open since 2023, still
`needs-review`), and the Kubernetes `UserNamespacesSupport` feature gate (beta
since v1.30, still beta at v1.35) is explicitly scoped to runtimes that use
Linux namespaces for isolation and **excludes Kata** by design. Industry
microVM-sandbox platforms (E2B, Fly, Gitpod/Ona, Daytona, Modal) don't run
rootless podman nested in Kata pods either — they drive Firecracker or
cloud-hypervisor directly, or use gVisor, not Kubernetes + Kata + nested
podman. The closest published pattern is Coder's own
`kubernetes-podman` community template, which is **rootless podman with the
default (runc) runtime**, no Kata, no `runtimeClassName`. The user's thesis
("everyone is doing this") is not borne out by public evidence.

## Findings

### 1. Kubernetes userns feature gate

- `UserNamespacesSupport` is **beta in Kubernetes v1.35** (beta since v1.30),
  not yet GA. ([k8s docs][k8s-userns])
- Runtime requirements: containerd >= 2.0 OR CRI-O >= 1.25, plus crun >= 1.9
  or runc >= 1.2, plus Linux >= 6.3. ([k8s docs][k8s-userns])
- Explicitly scoped: *"This page is applicable for container runtimes using
  Linux namespaces for isolation"* — Kata uses VMs, so `spec.hostUsers: false`
  is **not in scope for Kata**. ([k8s docs][k8s-userns])
- Mechanism uses kubelet-owned subuid/subgid + `getsubids`; it bypasses the
  in-pod `newuidmap` path, but only for the *outer* pod. It would not help a
  nested podman inside a Kata guest because Kata doesn't plumb it through.
- Kata upstream tracking issue for userns support:
  [kata-containers#8170 "support user namespace"][kata-8170] — open, no
  merged implementation as of April 2026. Design discussion stalled on
  idmap-mount support in virtio-fs.

Conclusion: the K8s feature gate does **not** solve #977.

### 2. Kata Containers upstream docs

- No documented "rootless podman inside a Kata pod" pattern on
  docs.katacontainers.io or in the kata-containers repo.
- [kata-containers#8170][kata-8170]: guest-side user namespaces are a
  **requested feature, not implemented**. Blocked on virtio-fs idmap-mount
  support and upstream containerd/runc integration.
- [kata-containers#9495][kata-9495] and [#11861][kata-11861]: "nested
  container" issues are about running Kata *inside* a container (the
  opposite direction) and are consistently "don't do that" / "increase
  /dev/shm".
- No `enable_user_ns` or equivalent knob exists in `configuration.toml`.
  `sandbox_cgroup_only` is a cgroup-placement flag, unrelated to userns
  (see [#2539][kata-2539], [#3038][kata-3038]).
- There is a separate "rootless Kata" mode (running the QEMU VMM as a
  non-root host user — [gabibeyer gist][kata-rootless-gist]); this is
  about the host side, orthogonal to nested podman inside the guest.

### 3. Coder templates

- Coder's community template
  [`kubernetes-podman`][coder-kubernetes-podman] is the canonical rootless
  podman pattern. It sets `runAsUser: 1000`, `fsGroup: 1000`, disables
  AppArmor via annotation, mounts a PVC, uses a pre-built image with
  podman pre-configured. **It does NOT set `runtimeClassName: kata`** — it
  relies on the default runtime (runc + host kernel).
- Coder's own tracking issue for rootless podman guidance
  ([coder#21633][coder-21633], Feb 2026) acknowledges the 3-year-old
  template is the current recommendation and needs a rewrite; it flags
  `userns="host"` as a common shortcut with security trade-offs.
- No Coder-published template combines Kata runtime + nested podman.

### 4. Industry patterns (microVM sandboxes)

Sources: [emirb microVM 2026 survey][emir-microvm],
[Northflank comparisons][northflank-e2b-modal],
[Modal blog][modal-blog].

- **E2B**: Firecracker microVMs driven directly by their own control plane
  (not Kubernetes + Kata + nested podman). ~150 ms cold start.
- **Modal**: gVisor (user-space syscall interception), not microVMs. Chose
  gVisor for `nvproxy`/GPU support.
- **Fly Machines / Sprites**: Firecracker, directly managed; not nested in
  Kubernetes.
- **Gitpod / Ona** (rebranded Sep 2025): ephemeral VMs per agent, VMM
  undisclosed but **not** documented as Kata-in-K8s.
- **Daytona, Railway**: dedicated-kernel sandboxes, VMM undisclosed.
- **Podman + libkrun**: Red Hat's in-tool microVM path; podman itself can
  launch krun microVMs. This is distinct from "podman nested in a Kata
  pod" and runs on a regular host, not a Kata guest.

No surveyed platform publicly documents the stack "Kubernetes pod with
`runtimeClassName: kata` running nested rootless podman". Platforms that
need microVM isolation drive the microVM manager directly.

### 5. Sidero Labs specifics

- [siderolabs/extensions#24][sl-24] (closed): added the Kata extension —
  upstream Kata, no userns patches.
- [siderolabs/extensions#431][sl-431] (open): request to support
  **Sysbox** as an alternative runtime class — Sysbox is explicitly
  designed for nested container engines (docker/podman/k8s inside a pod)
  using shiftfs/idmapped mounts, **without a VM**. Not implemented.
- [siderolabs/pkgs#1360][sl-userfaultfd] (closed): enabled
  `CONFIG_USERFAULTFD` in Talos host kernel — unrelated to guest kernel
  userns.
- No siderolabs issue specifically about "podman in Kata pod" or Kata
  guest-kernel userns multi-line uid_map behaviour.

### 6. Kata configuration knobs

Audit of `configuration.toml` options relevant to nested userns/rootless
podman:

| Knob | Effect | Helps #977? |
| --- | --- | --- |
| `sandbox_cgroup_only` | Host-side cgroup consolidation | No |
| `rootless` (hypervisor section) | Run QEMU VMM as non-root *on the host* | No |
| `virtio_fs_extra_args` / `virtio_fs_cache` | virtio-fs tuning | No (idmap support is the gap) |
| `disable_guest_selinux` | SELinux inside guest | N/A (no LSM detected in probes) |
| `kernel_params` (annotation) | Pass boot args to guest kernel | Possibly — could try `user_namespace.enable=1` or equivalent if the Kata kernel build disables unprivileged userns |
| `enable_annotations` | Allow per-pod config overrides | Meta |

There is **no `enable_user_ns` knob**. Guest-kernel userns behaviour is a
function of how the Kata guest kernel was compiled (`CONFIG_USER_NS`,
`CONFIG_USER_NS_UNPRIVILEGED`) and any agent-side confinement.

## Recommendation

**The Option C probe plan still makes sense, but scope it tightly.** No
off-the-shelf pattern exists to pivot to: Kata upstream userns is a
three-year-old unresolved feature request, K8s `hostUsers: false` is
explicitly out of scope for Kata, and every public microVM-sandbox
platform avoids the "Kata + nested podman in K8s" stack entirely. That
said, the probe should be time-boxed: its real job is to distinguish
"Kata guest kernel is missing `CONFIG_USER_NS_UNPRIVILEGED`" (cheap fix —
rebuild or pass kernel param) from "kata-agent confines uid_map writes"
(blocked on upstream [#8170][kata-8170], indefinite). If the probe
points at the latter within a day or two, **pivot to Option A or B**
(privileged rootful podman in a Kata-isolated pod) — that matches the
posture Coder's community template already uses (rootless on host, but
still no Kata) and is honest about the current state of the art.
Simultaneously, consider opening a siderolabs/extensions feature request
to surface the guest-kernel config (similar in spirit to Sysbox request
[#431][sl-431]).

## Sources

- [Kubernetes — User Namespaces docs][k8s-userns]
- [kata-containers#8170 — support user namespace][kata-8170]
- [kata-containers#9495 — Cannot run kata container inside a container][kata-9495]
- [kata-containers#11861 — vsock timeout in nested container][kata-11861]
- [kata-containers#2539][kata-2539], [#3038][kata-3038] — sandbox_cgroup_only
- [gabibeyer gist — rootless Kata + podman on host][kata-rootless-gist]
- [coder/community-templates — kubernetes-podman][coder-kubernetes-podman]
- [coder/coder#21633 — comprehensive rootless podman guide (2026-02)][coder-21633]
- [siderolabs/extensions#24 — add kata runtime][sl-24]
- [siderolabs/extensions#431 — Support Sysbox][sl-431]
- [siderolabs/pkgs#1360 — CONFIG_USERFAULTFD][sl-userfaultfd]
- [emirb — State of MicroVM Isolation in 2026][emir-microvm]
- [Northflank — E2B vs Modal][northflank-e2b-modal]
- [Modal — Top AI Code Sandbox Products 2025][modal-blog]

[k8s-userns]: https://kubernetes.io/docs/concepts/workloads/pods/user-namespaces/
[kata-8170]: https://github.com/kata-containers/kata-containers/issues/8170
[kata-9495]: https://github.com/kata-containers/kata-containers/issues/9495
[kata-11861]: https://github.com/kata-containers/kata-containers/issues/11861
[kata-2539]: https://github.com/kata-containers/kata-containers/issues/2539
[kata-3038]: https://github.com/kata-containers/kata-containers/issues/3038
[kata-rootless-gist]: https://gist.github.com/gabibeyer/4a80ca0fa4158bb40d7605c37aa003f6
[coder-kubernetes-podman]: https://github.com/coder/community-templates/tree/main/kubernetes-podman
[coder-21633]: https://github.com/coder/coder/issues/21633
[sl-24]: https://github.com/siderolabs/extensions/issues/24
[sl-431]: https://github.com/siderolabs/extensions/issues/431
[sl-userfaultfd]: https://github.com/siderolabs/pkgs/issues/1360
[emir-microvm]: https://emirb.github.io/blog/microvm-2026/
[northflank-e2b-modal]: https://northflank.com/blog/e2b-vs-modal
[modal-blog]: https://modal.com/blog/top-code-agent-sandbox-products
