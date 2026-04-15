# Design: GitOps-managed Coder template sync

**Issue:** [anthony-spruyt/spruyt-labs#934](https://github.com/anthony-spruyt/spruyt-labs/issues/934)
**Related:** [container-images#458](https://github.com/anthony-spruyt/container-images/issues/458) (new `coder-gitops` image)
**Date:** 2026-04-15

## Goal

Automate `coder templates push` via Flux so changes under `coder/templates/**` reconcile on merge to `main`. Eliminate the manual push step.

## Non-goals

- Version-gating by Git tag.
- Parallel per-template Jobs (only one template today).
- Automated orphan-token cleanup.

## Architecture

Two decoupled workloads in `cluster/apps/coder-system/coder-template-sync/`:

1. **Template-push Job** — triggered by `configMapGenerator` hash change on template content. Runs `coder templates push` for each `coder/templates/*/`.
2. **Token-rotation CronJob** — weekly self-renewal of the `gitops-bot` Coder session token.

Both share image `ghcr.io/anthony-spruyt/coder-gitops:<v>` (built under container-images#458), which bundles the `coder` CLI + `kubectl` + helper scripts.

### Directory layout

```text
cluster/apps/coder-system/coder-template-sync/
├── ks.yaml                          # Flux Kustomization
└── app/
    ├── kustomization.yaml           # configMapGenerator hashing coder/templates/**
    ├── kustomizeconfig.yaml         # nameReference so Job picks hashed ConfigMap name
    ├── rbac.yaml                    # ServiceAccount + Role + RoleBinding
    ├── job.yaml                     # template-push Job (hash-triggered)
    ├── cronjob-rotation.yaml        # weekly token rotation
    ├── secret-bootstrap.sops.yaml   # initial token, ssa: IfNotPresent
    └── network-policy.yaml          # CiliumNetworkPolicy egress restriction
```

The new Kustomization is referenced from the existing `cluster/apps/coder-system/coder/ks.yaml` or its own top-level Kustomization file (decided in plan).

## Components

### ConfigMap (Kustomize `configMapGenerator`)

Generates `coder-templates-<hash>` ConfigMap from `coder/templates/**/*.tf`, `*.hcl`, `*.md`, `*.tftpl`. `kustomizeconfig.yaml` wires `spec.template.spec.volumes[*].configMap.name` so the Job references the hashed name. Hash change ⇒ new Job name ⇒ runs once.

### Template-push Job (`job.yaml`)

- Runs under ServiceAccount `coder-template-sync` (no RBAC needed — reads mounted files + Secret only).
- Mounts ConfigMap at `/templates` (read-only).
- Mounts Secret `coder-gitops-bot-token` as env `CODER_SESSION_TOKEN`.
- Entrypoint: `/usr/local/bin/push-templates.sh` which:
  1. `coder login $CODER_URL --token "$CODER_SESSION_TOKEN"`.
  2. Loop `for dir in /templates/*/`; `coder templates push "$(basename "$dir")" --directory "$dir" --yes || failed+=("$name")`.
  3. Exit non-zero if `${#failed[@]} -gt 0`, listing failures.
- `backoffLimit: 3`, `ttlSecondsAfterFinished: 86400`, `restartPolicy: Never`.

### Token-rotation CronJob (`cronjob-rotation.yaml`)

- Schedule: `0 2 * * 0` (Sun 02:00). `concurrencyPolicy: Forbid`.
- Runs under ServiceAccount `coder-token-rotation` with Role scoped to `get/patch` on Secret `coder-gitops-bot-token`.
- Entrypoint: `/usr/local/bin/rotate-token.sh` which:
  1. `coder login $CODER_URL --token "$OLD_TOKEN"`.
  2. `NEW=$(coder tokens create --name gitops-bot-$(date -u +%Y%m%d%H%M%S) --lifetime 720h)`.
  3. `kubectl patch secret coder-gitops-bot-token --type=merge -p "{\"stringData\":{\"token\":\"$NEW\"}}"`.
  4. Parse old token ID (stored in annotation or derived from JWT), `coder tokens remove <old-id>`.
- 720h (30d) lifetime with weekly rotation leaves 23d slack.

### Bootstrap Secret (`secret-bootstrap.sops.yaml`)

- `Secret/coder-gitops-bot-token` with SOPS-encrypted initial token.
- Annotations:
  - `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` — Flux seeds once, then leaves runtime mutations alone.
- Operator mints initial token manually (runbook): `coder tokens create --user gitops-bot --lifetime 720h`, then re-seals with SOPS.
- If rotation fails long enough for the token to expire, delete the live Secret; Flux re-seeds from SOPS on next reconcile.

### RBAC (`rbac.yaml`)

Two ServiceAccounts, both in `coder-system`:

- `coder-template-sync` — no Role. Reads only mounted ConfigMap + Secret (granted implicitly via pod spec).
- `coder-token-rotation` — Role with `get,patch` on `secrets` `resourceNames: ["coder-gitops-bot-token"]`.

### NetworkPolicy (`network-policy.yaml`)

`CiliumNetworkPolicy` egress for both pods:

- DNS to `kube-system/kube-dns` on 53/UDP.
- Kube-apiserver (entity: `kube-apiserver`) on 6443/TCP — for `kubectl patch`.
- Coder service `coder-system/coder` on 7080/TCP (or whatever the service port is — confirm in plan).

No ingress needed.

### PSA / Pod security

Both pods:

- `runAsNonRoot: true`, `runAsUser: 1000`, `runAsGroup: 1000`, `fsGroup: 1000`.
- `readOnlyRootFilesystem: true`.
- `allowPrivilegeEscalation: false`.
- `capabilities.drop: [ALL]`.
- `seccompProfile: RuntimeDefault`.
- tmpfs `emptyDir` at `/tmp` and `/home/coder` (coder CLI config).

## Prerequisites

1. **Coder server config**: bump `CODER_MAX_TOKEN_LIFETIME` to `8760h` (1yr) or at minimum `2160h` (90d) to permit 720h rotation tokens. Edit via `cluster/apps/coder-system/coder/app/values.yaml` or ConfigMap — confirm in plan.
2. **Headless Coder user `gitops-bot`**:
   ```bash
   coder users create --username gitops-bot --email gitops-bot@<domain> --login-type none
   ```
   Role: template admin (scoped, not owner). Confirm exact role name in Coder RBAC docs during plan.
3. **Initial token** minted and SOPS-sealed.
4. **Image `ghcr.io/anthony-spruyt/coder-gitops:<v>`** published (container-images#458).

## Data flow

**Template push (on template change):**

```text
git push → Flux reconciles → ConfigMap hash changes → new Job name →
  Job runs → coder login → for dir in /templates/*: coder templates push →
  exit 0 if all OK, non-zero on any failure
```

**Token rotation (weekly):**

```text
CronJob fires → coder login with current token →
  coder tokens create (new 720h token) →
  kubectl patch secret →
  coder tokens remove <old-id>
```

## Error handling

| Scenario                           | Behaviour                                                                   |
| ---------------------------------- | --------------------------------------------------------------------------- |
| Push fails for one template        | Loop continues; Job exits non-zero; Flux/Alertmanager surface failure       |
| Push fails transiently             | `backoffLimit: 3` retries                                                   |
| Rotation token-create fails        | Job fails; old token still valid until expiry; alert                        |
| Rotation patch fails after create  | Orphan new token; runbook: manually revoke, re-run                          |
| Token expires before next rotation | Runbook: mint new token, re-seal SOPS, delete live Secret, Flux re-seeds    |
| Coder server unreachable           | Job fails with backoff; alert after final retry                             |

## Security properties

- Least-privilege headless user (template admin, not owner).
- Token never leaves cluster (SOPS at rest, Secret in memory only).
- Restricted PSA, dropped caps, RORFS, seccomp.
- Network egress limited to kube-apiserver, Coder service, DNS.
- Token rotation weekly; compromise window ≤ 7 days.
- RBAC scoped to single named Secret.

## Testing / verification

1. **Bootstrap**: create `gitops-bot` user, mint token, seal with SOPS, push.
2. **First sync**: verify Job runs on merge, check `coder templates versions list devcontainer` shows new version.
3. **Workspace admission**: create workspace against new version, confirm it admits under PSA=restricted (closes the pain from #932).
4. **Idempotence**: re-merge an unrelated change — no new Job should spawn (hash unchanged).
5. **Rotation**: manually trigger CronJob (`kubectl create job --from=cronjob/coder-token-rotation manual-test`), verify:
   - new token minted (`coder tokens list --user gitops-bot`);
   - Secret updated (`kubectl get secret … -o jsonpath='{.metadata.resourceVersion}'` changes — do NOT print data);
   - old token revoked.
6. **Manual escape hatch**: `coder templates push devcontainer -y` from a dev machine still works.

## Open items for the plan

- Exact Coder service port and scheme (internal DNS).
- Exact role name for "template admin" in current Coder version.
- Whether to bump `CODER_MAX_TOKEN_LIFETIME` to 8760h or 2160h.
- Old-token-ID extraction: annotation on Secret vs parse from JWT.
- Whether the new Kustomization lives in existing `coder/ks.yaml` (depends-on `coder`) or its own top-level `ks.yaml`.
