---
name: add-workload
description: >
  Deploy a new Helm-based workload to the cluster end to end: issue, chart research, Flux and
  Kustomize manifests, priority tier, VPA, network policies, ingress, docs, and validation. Use
  when the user asks to add, deploy, or install a new app, service, or Helm chart in the
  cluster. Not for upgrading or reconfiguring an app that already exists.
argument-hint: <app-name>
arguments: [app]
---

# Add Workload

Target app: `$app`.

This skill is the order of work. The conventions live in rules that load when you touch matching files: `patterns.md` for any `cluster/**/*.yaml`, `ingress-and-certificates.md` for ingress, `documentation.md` for READMEs. Follow them over anything you remember.

## 1. Issue

Find or create the issue per the GitHub rule, using `.github/ISSUE_TEMPLATE/feature_request.yml`. qa-validator and cluster-validator both need its number.

## 2. Requirements

Look things up before asking. Ask the user only for what the repo and upstream can't tell you:

- Chart source, or the image if there is no chart
- Namespace: new or existing
- Priority tier: propose one with a reason from `docs/workload-classification.md`
- Dependencies: database, secrets, other apps
- Access: LAN-only (`.lan.${EXTERNAL_DOMAIN}`), public, or none

## 3. Research the chart

- Read the upstream `values.yaml` for the version you will pin (Context7, or `raw.githubusercontent.com`). Note where `priorityClassName`, `resources`, `securityContext`, and `tolerations` sit; paths differ per chart.
- Find a `values.schema.json` URL and confirm it returns 200: `curl -sL -o /dev/null -w '%{http_code}' <url>`. With none, use `# #yaml-language-server: $schema=TODO` as the header.
- No chart, only an image: use bjw-s app-template through the `app-template` OCIRepository.

## 4. Copy a reference app

Mirror a recent app with the same needs instead of writing manifests from memory. List recent additions with `git log --diff-filter=A --format='%h %s' -- 'cluster/apps/*/*/ks.yaml' | head`.

| Need                                           | Reference                                 |
| ---------------------------------------------- | ----------------------------------------- |
| Chart from a HelmRepository, CNPG, ESO, ingress | `cluster/apps/temporal-system/temporal/`  |
| app-template (image only)                       | `cluster/apps/cloudflare-system/cloudflared/` |

## 5. Write the files

- **Chart source** (new only): `cluster/flux/meta/repositories/helm/` or `oci/`, listed in that directory's `kustomization.yaml`.
- **Namespace** (new only): `namespace.yaml` with PSA `restricted` unless the workload can't run restricted, the namespace `kustomization.yaml`, and `./<namespace>` in `cluster/apps/kustomization.yaml`.
- **App**: `ks.yaml` and `app/` with `kustomization.yaml`, `kustomizeconfig.yaml`, `release.yaml`, `values.yaml`, `vpa.yaml`, plus `network-policies.yaml`, secrets, and database manifests as needed.
- **values.yaml**: `priorityClassName` and `resources` on every container. CPU limit is request × the tier multiplier in `docs/workload-classification.md`; no CPU limit for `critical-infrastructure`.
- **HelmRelease**: set `interval: 4h`. Leave out `timeout`, `install`, `upgrade`, and `rollback`; Kyverno injects them (`cluster/apps/kyverno/policies/app/helmrelease-defaults.yaml`).
- **Network policies**: CiliumNetworkPolicies in `app/network-policies.yaml`, shaped like the reference app's. Allow only the ingress and egress the app needs.
- **Ingress**: goes under `cluster/apps/traefik/traefik/ingress/<namespace>/`, never in the app directory. Add the directory to `ingress/kustomization.yaml` and the app to `dependsOn` in `cluster/apps/traefik/traefik/ks.yaml`.
- **Docs**: add the workload to its tier table in `docs/workload-classification.md`. Write a README only when there is something non-obvious to say.

## 6. Validate and ship

1. Run qa-validator with the issue number; fix until APPROVED.
2. Stage each file by name and commit with `Ref #<issue>`, then push.
3. Run cluster-validator with the issue number.
4. Check the pods are healthy. If anything can't connect, run cnp-drop-investigator.
5. Close the issue once validation passes.
