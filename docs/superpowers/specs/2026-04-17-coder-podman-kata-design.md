# Coder Podman-in-Kata — Option C Research Spike (Spec)

**Ref:** [#977](https://github.com/anthony-spruyt/spruyt-labs/issues/977)
**Date:** 2026-04-17
**Author:** brainstorm session (Claude + Anthony)
**Supersedes:** none

## 1. Goal & Non-Goals

### Goal

Make rootless (preferred) or unprivileged-rootful podman work inside a Coder workspace pod running under `runtimeClassName: kata`, without relaxing `coder-system` PSA below `baseline` and without `privileged: true` on the workspace container.

### Success criteria

1. Rootless `podman run hello-world` succeeds inside a Coder workspace pod on overlay or fuse-overlayfs storage (not vfs).
2. `./lint.sh` (MegaLinter) runs to completion in that workspace.
3. Envbuilder kaniko build path still works (existing template rebuild path unaffected).

### Non-goals

- Option A from #977 (relax `coder-system` PSA in place). Rejected.
- Option B from #977 (namespace split). YAGNI'd; revisit only if C is abandoned.
- Kata extension rollout to non-worker nodes — all three ms-01 workers already kata-ready; control planes out of scope.

### Final landing scope

Full Coder template refactor required by the winning fix. Not limited to `startup_script`. Includes `security_context`, `post-create.sh`, `lint.sh`, storage driver config, `XDG_RUNTIME_DIR` setup, and any other consumer changes the winning configuration demands.

## 2. Architecture

### Probe phase (C1 → C2 → C3)

- Ephemeral `kubectl run` pods on any kata-ready worker (`kata.spruyt-labs/ready=true`), `runtimeClassName: kata`.
- Image: `fedora:latest` with `podman shadow-utils strace` preinstalled (or `dnf -y install` at start).
- Each probe is a standalone reproducer. Results logged to an appendix in this spec.
- Probes never touch Coder templates.

### Landing phase (after green probe)

Apply winning config at the narrowest scope possible. Candidate landing sites (one or more depending on the fix):

- **Kata runtime config** — patch under `cluster/apps/kube-system/kata-runtimeclass/` or introduce a new `RuntimeClass: kata-workspace` variant.
- **Talos sysctl/kernel args** — `talos/talconfig.yaml` ms01 anchor. Requires schematic regen (factory) + sequential `talos-upgrade`.
- **Kata extension version pin** — factory schematic change. Sequential upgrade.
- **Coder template** — `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf`. Add `runtime_class_name = "kata"` (if absent). Add storage/XDG setup to `startup_script`.
- **Workspace consumer scripts** — `.devcontainer/post-create.sh`, `lint.sh` updates as required.

### Validation

Restart one existing workspace → run the three success criteria in order.

## 3. Probe Plan

Base reproducer (all probes):

```sh
unshare -U sh -c 'newuidmap $$ 0 1000 1 1 100000 65536; echo rc=$?'
```

`rc=0` = pass. `EPERM` = fail.

### C1 — breadth-first config sweep

Run in order; stop at first green.

1. **Hypervisor** — create `RuntimeClass: kata-qemu` alongside existing CLH `kata`. Re-run repro.
2. **Guest sysctls** — `sysctl -w kernel.unprivileged_userns_clone=1`, `user.max_user_namespaces=15000`, `kernel.apparmor_restrict_unprivileged_userns=0`.
3. **Kata OCI annotations** — `io.katacontainers.config.hypervisor.kernel_params=+user_namespace.enable=1`, `...disable_new_netns=false`.
4. **kata `configuration.toml`** — handler override: `sandbox_cgroup_only=false`, `disable_guest_seccomp=true`.
5. **`procMount: Unmasked`** — pod securityContext, with and without `hostUsers: false`.
6. **`allowPrivilegeEscalation: true` + non-root** — sometimes blocks NO_NEW_PRIVS from gating setuid helpers.

Deliverable: results table (`hack/kata-podman-probes/results-YYYY-MM-DD.md`) + appendix update in this spec.

### C2 — guest confinement deep-dive

Only if C1 all-red. Requires explicit user approval to proceed (decision gate).

- Dump kata-agent seccomp: `grep Seccomp /proc/1/status`; extract BPF via `seccomp-tools`.
- `dmesg` from guest (kata debug console or privileged debug pod) during repro.
- Enumerate LSMs: `/sys/kernel/security/*`, bpf-lsm programs, landlock.
- `strace -f newuidmap ...` to pinpoint failing syscall.

### C3 — version bisect

Only if C2 yields no config-addressable root cause. Requires user approval.

- Bisect `siderolabs/kata-containers` extension versions via factory.
- If guest kernel is the boundary, flag escalation to Q3 option (c) — custom kernel — and re-brainstorm.

## 4. Data Flow & Decision Gates

```text
[C1 probe 1] → green? → land fix → validate workspace → done
       ↓ red
[C1 probe 2] → green? → land → validate → done
       ↓ red
  ... probes 3-6 ...
       ↓ all red
[USER APPROVAL GATE] → proceed to C2?
       ↓ yes
[C2 deep-dive] → root cause found? → config fix if possible → land → done
       ↓ no clear config path
[USER APPROVAL GATE] → proceed to C3?
       ↓ yes
[C3 version bisect] → good boundary found? → pin version → land → done
       ↓ no
[USER DECISION] → abandon C (re-brainstorm B), or escalate to custom kernel/image (Q3 option c/d)
```

Gates are explicit user approvals (no auto-advance). This keeps the uncapped timeline from drifting into unwanted escalation.

## 5. Artefacts in Repo

| Path                                                                | Purpose                                                                |
| ------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `docs/superpowers/specs/2026-04-17-coder-podman-kata-design.md`     | This spec.                                                             |
| `hack/kata-podman-probes/probe.sh`                                  | Reproducer harness. Kept in-tree for re-validation after kata bumps.   |
| `hack/kata-podman-probes/README.md`                                 | How to run probes.                                                     |
| `hack/kata-podman-probes/results-YYYY-MM-DD.md`                     | Per-run results table. Latest appended to this spec as appendix.       |

Landing artefacts (TBD, depend on winning probe; enumerated here as placeholders to be filled in the implementation plan):

- `cluster/apps/kube-system/kata-runtimeclass/` — patch or new RuntimeClass.
- `talos/talconfig.yaml` — ms01 anchor sysctl or extension changes.
- `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf` — template updates.
- `.devcontainer/post-create.sh`, `lint.sh` — consumer updates.

## 6. Error Handling & Rollback

- Probe pods are ephemeral — `kubectl delete` rolls back.
- Config landing: `git revert` → Flux reconciles → template-sync reverts Coder template on next run.
- Talos/sysctl/extension changes: reverse `talos-upgrade` agent sequence (control planes one at a time, workers with Ceph HEALTH_OK waits; though this spec only touches workers).
- Post-land validation failure: existing workspaces keep running until user restarts; baseline (broken podman) is no worse than today.

## 7. Testing

- Per-probe: repro exit code + `dmesg` diff.
- Post-land: `task dev-env:lint` (local host), `./lint.sh` inside Coder workspace, envbuilder rebuild of one template.
- qa-validator before commit. cluster-validator after push (template-sync is Flux-managed).

## 8. Open Items (to be resolved during plan)

- Whether to introduce a separate `RuntimeClass: kata-workspace` or patch the existing `kata` class. Depends on blast-radius of winning config (does it affect qdisc DaemonSet or other kata consumers?).
- Exact storage driver choice (overlay vs fuse-overlayfs) — decided once rootless works; both meet success criterion 1.

## Appendix A — Probe Results

*Empty. Populate as probes run.*
