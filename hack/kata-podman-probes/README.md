# Kata Podman Probes

Research harness for [#977](https://github.com/anthony-spruyt/spruyt-labs/issues/977).
Diagnoses why rootless podman fails inside Kata-runtime pods.

## Quickstart

```bash
./hack/kata-podman-probes/probe.sh 1
```

Each probe spawns an ephemeral pod on a kata-ready worker, runs the userns reproducer,
prints pass/fail, deletes the pod.

## Reproducer

The probe runs as root inside the container — the reproducer tests multi-line `uid_map` writes, which fail even for root with CAP_SETUID per issue #977 diagnosis.

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
