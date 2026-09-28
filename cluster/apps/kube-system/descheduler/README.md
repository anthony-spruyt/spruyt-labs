# descheduler - Pod Rebalancing

## Overview

Runs every 30 minutes to rebalance pods across nodes (duplicates, topology spread, low/high utilisation) and to clear failed or crash-looping pods. It pairs with the Kyverno `add-default-topology-spread` policy, which only injects soft `ScheduleAnyway` constraints - the descheduler is what enforces them after the fact.

## Operations

### Namespace exclusions are duplicated per plugin

Namespaces carry a `descheduler.kubernetes.io/exclude: "true"` label, but it is not yet what excludes them. Every plugin in `app/values.yaml` repeats the same `exclude` list, a leftover from an upstream selector bug fixed in v0.36.0 (kubernetes-sigs/descheduler#1853). Moving to `DefaultEvictor.namespaceLabelSelector` is tracked in #641.

Until then, to exclude a namespace add it to **every** plugin's list and label its namespace. `flux-system` gets its label through a patch in `flux-instance/app/values.yaml` because flux-operator owns that Namespace.
