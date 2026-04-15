# Phase 1 — Unprivileged Coder Workspaces (rootless Podman)

**Tracking issue:** #921 (umbrella) · **This phase:** #932 · **Follow-up:** #933 (Kata)
**Date:** 2026-04-15

## Problem

Coder workspaces run with `privileged: true` (`coder/templates/devcontainer/main.tf:434`) to support envbuilder's nested dockerd, pulled in by the `ghcr.io/devcontainers/features/docker-in-docker` feature in `.devcontainer/devcontainer.json`. With AI agents executing arbitrary code in these workspaces, a container escape = root on the Talos node.

The root cause is not "we need Kata" — it's "we have a privileged daemon in the pod." Remove the daemon, and the pod becomes eligible for PSA `restricted`, which also unblocks #910 (ssh-key-rotation under restricted PSA).

## Non-Goals

- Kata Containers adoption (→ #933, Phase 2, defense-in-depth on top of this work)
- Coder control plane HelmRelease changes beyond what PSA requires
- Any workload outside `coder-system` namespace
- Changes to unrelated custom images

## Approach

Replace the Docker-in-Docker devcontainer feature with **rootless Podman**, installed inline via `.devcontainer/setup-devcontainer.sh`. Podman's `podman-docker` package symlinks `/usr/bin/docker` → `podman`, so MegaLinter and any `docker run …` code paths work unchanged.

The same `devcontainer.json` is consumed by both local VS Code (Docker Desktop/WSL on the user's PC) and envbuilder in Coder. Both environments get Podman; both drop their need for a privileged dockerd.

Separately, lock `coder-system` to PSA `restricted` — staged (warn → audit → enforce) so violations surface before they block. Fix #910 by replacing the `alpine/k8s:1.35.3 + apk add openssh-keygen` at-runtime pattern with a dedicated custom image built in `anthony-spruyt/container-images`.

## Rejected Alternatives

- **Keep DinD, add Kata only** — still runs dockerd as root inside the microVM; Kata becomes the only boundary and dockerd-in-microVM has performance quirks. Fixes symptom, not cause.
- **Community `podman` devcontainer feature** — third-party, may misbehave under
  envbuilder's build-time feature execution; inline install in
  `setup-devcontainer.sh` matches existing repo idiom (Claude CLI, safe-chain).
  Versions follow Ubuntu apt repo (same model as every other `apt-get install`
  in the script) rather than being pinned in-repo — acceptable since Podman's
  CLI/Docker compat surface is stable and any breakage surfaces at devcontainer
  rebuild, not in production.
- **Third-party minimal base image** (Wolfi, distroless) for the ssh-key-rotation image — introduces a new supply-chain trust root. The `container-images` repo already standardises on digest-pinned `alpine:<ver>@sha256:…` (see `chrony/Dockerfile`); follow that pattern.
- **Sysbox / gVisor** — Sysbox has no official Talos extension. gVisor syscall coverage breaks DinD-style workloads.

## Design

### Unit 1 — devcontainer (local PC + Coder, single source of truth)

**`.devcontainer/devcontainer.json`**
- Remove `ghcr.io/devcontainers/features/docker-in-docker`.
- No other feature changes.

**`.devcontainer/setup-devcontainer.sh`**
Append (or factor into a dedicated function) an install block:

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  podman podman-docker fuse-overlayfs uidmap slirp4netns
# podman-docker provides /usr/bin/docker → podman symlink
# uidmap provides newuidmap/newgidmap for rootless user namespaces
# slirp4netns provides rootless user-mode networking
```

**Post-install verification (extend `post-create.sh` checks):**
- `docker --version` reports Podman
- `docker run --rm hello-world` succeeds (already present)
- `/etc/subuid` and `/etc/subgid` contain an entry for `vscode` (baked into `mcr.microsoft.com/devcontainers/base:jammy`; verify, add if missing)

**What works unchanged:** MegaLinter (`task dev-env:lint`), `gh`, pre-commit, language toolchains, claude CLI.

**What changes for the user:** `docker` is Podman. Day-to-day commands identical. `docker compose` is available via `podman-compose` (install if needed; out of scope unless a current workflow depends on it — none found in scan).

**What's explicitly not supported post-change:**
- Privileged containers inside the workspace (`docker run --privileged`)
- Mounting `/var/run/docker.sock` into nested containers
- BuildKit drivers requiring a privileged builder

### Unit 2 — Coder workspace template

**`coder/templates/devcontainer/main.tf`**

Pod-level `security_context`:
```hcl
security_context {
  run_as_user      = 1000
  run_as_group     = 1000
  fs_group         = 1000
  run_as_non_root  = true
}
```

Container `security_context`:
```hcl
security_context {
  privileged                 = false
  allow_privilege_escalation = false
  read_only_root_filesystem  = false  # Podman stores under $HOME
  capabilities {
    drop = ["ALL"]
  }
}
```

Remove the existing pod-level `run_as_user = 0` and the container-level `privileged = true`.

**Template version bump + re-push** (`coder templates push devcontainer`) after merge. Existing workspaces are nuked and recreated (confirmed acceptable).

### Unit 3 — `ssh-key-rotation` custom image (in `container-images` repo)

**Separate PR in `anthony-spruyt/container-images`.** Only referenced from Phase 1; not part of this repo's PR.

New directory `ssh-key-rotation/`:
- `Dockerfile` — `FROM alpine:3.23@sha256:<digest>` (match chrony's pin pattern)
- `apk add --no-cache openssh-keygen curl jq kubectl ca-certificates tzdata` at build time (matches the tools the existing rotation script actually uses — `curl` for GitHub API, `jq` for parsing, `kubectl patch` for the secret update)
- `apk upgrade --no-cache` for security patches
- Non-root UID 1000
- Entrypoint script bakes in the rotation logic (no more inline shell in the CronJob spec)

Publishes `ghcr.io/anthony-spruyt/container-images/ssh-key-rotation:<tag>` via existing release automation. Renovate tracks both the Alpine digest and the image tag.

### Unit 4 — ssh-key-rotation CronJob (this repo)

`cluster/apps/coder-system/coder/<cronjob-manifest>` (exact path TBD during planning):

- Image: `ghcr.io/anthony-spruyt/container-images/ssh-key-rotation:<pinned>`
- Remove inline shell script (moved into image)
- Pod `securityContext`: `runAsNonRoot: true`, `runAsUser: 1000` (matching the custom image), `seccompProfile: { type: RuntimeDefault }`, `fsGroup: 1000` for secret mount
- Container `securityContext`: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities.drop: [ALL]`
- `restartPolicy: Never`, `backoffLimit: 3`, `ttlSecondsAfterFinished: 86400` (retain logs for a day after failure)

Closes #910 once the next weekly run completes under restricted PSA.

### Unit 5 — `coder-system` namespace PSA

**Rollout order (staged, not atomic):**

1. **Commit 1 — warn + audit labels:**
   ```yaml
   pod-security.kubernetes.io/warn: restricted
   pod-security.kubernetes.io/audit: restricted
   ```
   Generates warnings and audit events without blocking. Validators (cluster-validator) pick these up in the next run.
2. **Observation window (≥ 24h):** review `kubectl get events -n coder-system` and audit logs for violations. Fix any upstream helmrelease values that need adjustment.
3. **Commit 2 — enforce:**
   ```yaml
   pod-security.kubernetes.io/enforce: restricted
   ```
   Only merged once observation window is clean. This is the one-way door in Phase 1.

The Coder HelmRelease values may need an explicit `securityContext` override — verify during plan from upstream chart defaults.

## Data Flow

No data flow changes. Workspace pods still mount:
- `workspaces` PVC (code)
- `home` PVC (user dotfiles, Podman storage — critical for rootless)
- `ssh-signing-key` secret (read-only)
- `coder-workspace-env` secret (env vars)

Podman stores images and containers under `$HOME/.local/share/containers` — backed by the `home` PVC, so workspace restarts preserve pulled images.

## Error Handling

- **Podman install fails** → `setup-devcontainer.sh` exits non-zero, devcontainer build fails loudly (preferred over silent degradation).
- **`docker run hello-world` fails in `post-create.sh`** → existing check already reports this; no silent skip in non-Coder environments.
- **PSA violations after enforce** → blocks pod admission. Rollback: revert the enforce-label commit. Warn/audit stays, giving continued visibility.
- **ssh-key-rotation crash** → image now ships openssh-keygen, so the #910 root cause is gone. `restartPolicy: Never` + `ttlSecondsAfterFinished` preserves logs for inspection. Alertmanager alert on `KubeJobFailed` still fires.

## Validation

Per-unit:

| Unit | Check |
| --- | --- |
| 1 | Local VS Code devcontainer rebuilds; `docker --version` → Podman; `task dev-env:lint` passes |
| 2 | `kubectl get pod <workspace> -o yaml \| grep privileged` empty; pod runs as UID 1000 |
| 2 | `task dev-env:lint` passes inside a fresh Coder workspace |
| 3 | Custom image in `container-images` builds, scans clean, publishes to ghcr |
| 4 | Next scheduled CronJob run completes successfully under restricted PSA |
| 5 | `kubectl get ns coder-system -o yaml \| grep pod-security` shows `enforce=restricted` |
| 5 | No `FailedCreate` events in `coder-system` for 48h after enforce |

End-to-end:
- Fresh workspace starts under non-privileged template
- MegaLinter run inside workspace produces identical output to pre-change baseline
- #910 closed after one successful ssh-key-rotation cycle

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Rootless Podman quirk breaks a workload we didn't discover in scan | Medium | Staged rollout (devcontainer change first, observe; Coder template second); easy revert |
| PSA `enforce` breaks an unrelated coder-system workload | Low-Medium | Warn + audit observation window before enforce; revert label to roll back |
| Envbuilder's feature-execution model rejects the devcontainer change | Low | Inline install via `setup-devcontainer.sh` runs at `postCreate`, not feature time — avoids envbuilder feature quirks entirely |
| `docker compose` usage emerges post-change | Low | Out of scope; add `podman-compose` if needed |
| Podman storage on PVC has different IOPS profile than dockerd overlay2 | Low | Same Ceph-RBD backend; acceptable perf expected; benchmark during validation |

## Rollout Sequencing (PR structure)

1. **PR A (container-images repo):** new `ssh-key-rotation/` image. Merge + publish tag first — must exist before Phase 1 can reference it.
2. **PR B (spruyt-labs, this phase):**
   - Commit 1: devcontainer changes (Podman install, remove DinD feature)
   - Commit 2: Coder template security context change
   - Commit 3: ssh-key-rotation CronJob to new image + restricted-compliant pod spec
   - Commit 4: namespace PSA `warn` + `audit` labels
   - Commit 5 (merged separately after observation window): namespace PSA `enforce`

The split between commits 4 and 5 is the key sequencing decision — everything before commit 5 is trivially revertible; commit 5 is the cliff.

## Open Questions for Planning

- Exact Coder HelmRelease values needed for PSA restricted (verify against upstream chart defaults)
- Whether any Coder workspace feature (e.g., terminal session) currently relies on implicit privileged behaviour — test with disposable workspace before merging commit 2
- Observation window duration between PSA warn/audit and enforce — default 48–72h unless validation surfaces issues sooner

## Success Criteria (Phase 1)

- [ ] No `privileged: true` in any `coder-system` pod spec
- [ ] `.devcontainer/devcontainer.json` unchanged between local PC and Coder paths (single source of truth)
- [ ] MegaLinter works in both environments
- [ ] `coder-system` namespace at PSA `enforce=restricted`
- [ ] #910 closed
- [ ] #921 Phase 1 checkbox ticked; #933 (Phase 2) ready to start as clean follow-up
