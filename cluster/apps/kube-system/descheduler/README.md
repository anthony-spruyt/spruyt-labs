# descheduler - Pod Rebalancing

## Overview

Runs every 30 minutes to rebalance pods across nodes (duplicates, topology spread, low/high utilisation) and to clear failed or crash-looping pods. It pairs with the Kyverno `add-default-topology-spread` policy, which only injects soft `ScheduleAnyway` constraints - the descheduler is what enforces them after the fact.

## Operations

### Excluding a namespace

Label the namespace `descheduler.kubernetes.io/exclude: "true"`. `DefaultEvictor.namespaceLabelSelector` in `app/values.yaml` skips every labelled namespace for all plugins. `flux-system` gets its label through a patch in `flux-instance/app/values.yaml` because flux-operator owns that Namespace.

The selector is `DoesNotExist` on the key, so the value is ignored: `"false"` still excludes, and a typo in the key silently makes the namespace evictable. After labelling, confirm with `kubectl get ns -l descheduler.kubernetes.io/exclude`.
