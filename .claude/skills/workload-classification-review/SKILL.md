---
name: workload-classification-review
description: >
  Audit workload priority classes across docs/workload-classification.md, the manifests in
  cluster/apps, and the live cluster, then fix the mismatches. Use when the user asks to review
  priority classes or workload tiers, for the quarterly classification review, or after an
  incident involving resource contention or eviction.
---

# Workload Classification Review

`docs/workload-classification.md` is the source of truth for tiers, criteria, and CPU limit policy. Read it first.

## 1. Gather the three views

**Live:**

```bash
kubectl get deploy,sts,ds -A \
  -o custom-columns='NS:.metadata.namespace,KIND:.kind,NAME:.metadata.name,PRIORITY:.spec.template.spec.priorityClassName'
kubectl get priorityclasses
```

An empty `PRIORITY` means the pod falls back to `standard`.

**Code:**

```bash
grep -rn 'priorityClassName' cluster/apps --include='*.yaml'
for f in cluster/apps/*/*/app/values.yaml; do grep -q priorityClassName "$f" || echo "MISSING: $f"; done
```

Charts with several components can set the class per component; a single hit does not mean every pod is covered.

**Docs:** the tier tables and Known Gaps in `docs/workload-classification.md`.

## 2. List mismatches

| Workload | Doc | Code | Live | Fix |
| -------- | --- | ---- | ---- | --- |

- **Doc vs code**: decide which is right using the promotion and demotion triggers in the doc
- **Missing in code**: no explicit class, so it runs as `standard`
- **Missing in doc**: running but not listed
- **Code vs live**: Flux hasn't applied it; check the Kustomization before editing anything

Show the table to the user before changing tiers. Moving a workload between tiers is their call.

## 3. Fix

- **Code**: set `priorityClassName` at the path the chart expects (check upstream `values.yaml`), and keep the CPU limit at request × the tier multiplier.
- **Docs**: add, move, or remove workloads in the tier tables. Record anything you can't fix yet under Known Gaps.

Code changes under `cluster/` follow the normal validation flow: issue, qa-validator, commit, push, cluster-validator. Re-run the live query afterwards to confirm the classes applied.
