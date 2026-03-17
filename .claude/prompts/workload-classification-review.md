# Workload Classification Review

Review and maintain workload priority classifications to ensure consistency between documentation, code, and live cluster state.

Run this prompt quarterly or when adding/modifying workloads.

---

## Step 1: Gather Live Cluster State

Get all workloads with their priority classes:

```bash
# Deployments
kubectl get deployments -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,PRIORITY_CLASS:.spec.template.spec.priorityClassName,REPLICAS:.spec.replicas'

# StatefulSets
kubectl get statefulsets -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,PRIORITY_CLASS:.spec.template.spec.priorityClassName,REPLICAS:.spec.replicas'

# DaemonSets
kubectl get daemonsets -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,PRIORITY_CLASS:.spec.template.spec.priorityClassName'

# Priority class definitions
kubectl get priorityclasses -o custom-columns='NAME:.metadata.name,VALUE:.value,DEFAULT:.globalDefault'
```

---

## Step 2: Gather Code Configuration

Find all priorityClassName settings in code:

```bash
# Find all files with priorityClassName
grep -r "priorityClassName" cluster/apps --include="*.yaml" | grep -v "#"

# Find values.yaml files WITHOUT priorityClassName (relying on default)
for f in $(find cluster/apps -name "values.yaml"); do
  grep -q "priorityClassName" "$f" || echo "MISSING: $f"
done

# Check CNPG clusters
grep -r "priorityClassName" cluster/apps --include="*-cnpg-cluster.yaml"
```

---

## Step 3: Cross-Reference with Documentation

Read `docs/workload-classification.md` and compare:

1. **Live cluster** priority classes match **documentation** classifications
2. **Code** priority classes match **documentation** classifications
3. **All workloads** in cluster are **listed** in documentation

---

## Step 4: Identify Mismatches

Create a table of mismatches:

| Workload | Doc Says | Code Has | Live Has | Action |
|----------|----------|----------|----------|--------|
| example | high-priority | standard | standard | Update code OR update doc |

Categories:
- **Doc vs Code**: Documentation says one tier, code has another
- **Missing in Code**: Workload has no explicit priorityClassName (gets standard default)
- **Missing in Doc**: Workload exists but not documented
- **Live Mismatch**: Code and live don't match (Flux sync issue)

---

## Step 5: Apply Fixes

### 5a: Code Fixes (values.yaml)

For Helm charts, add priorityClassName at the appropriate level. Check upstream chart docs first.

Common patterns:
```yaml
# Top-level (some charts)
priorityClassName: high-priority

# Nested under deployment/pod spec (other charts)
deployment:
  priorityClassName: high-priority

# Or under specific component
server:
  priorityClassName: high-priority
```

### 5b: Documentation Fixes

Update `docs/workload-classification.md`:
- Add new workloads to appropriate tier table
- Move workloads between tiers if classification changed
- Remove workloads that no longer exist

### 5c: Commit Changes

```bash
# Code changes
git add cluster/apps/
git commit -m "fix(priority): align priorityClassName with classification"

# Doc changes (separate commit)
git add docs/workload-classification.md
git commit -m "docs(classification): update workload tier assignments"
```

---

## Step 6: Validate After Push

After Flux reconciles:

```bash
# Verify priority classes applied
kubectl get deployments -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,PRIORITY:.spec.template.spec.priorityClassName' | grep -v "<none>"

# Check for any pods still without priority (excluding system pods)
kubectl get pods -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,PRIORITY:.spec.priorityClassName' | grep "<none>" | grep -vE "^kube-system"
```

---

## Classification Reference

| Priority Class | Value | Criteria |
|----------------|-------|----------|
| critical-infrastructure | 1,000,000 | Cluster won't function without it |
| high-priority | 100,000 | Essential user-facing, observability, auth |
| standard | 10,000 | Business apps (default) |
| low-priority | 1,000 | Internal tools, gaming, hobby |
| best-effort | 100 | Batch jobs, preemptible |

### Promotion Triggers

- Causes cluster instability when throttled
- Critical services depend on it
- Outage impacts disaster recovery

### Demotion Triggers

- Can be offline without cluster impact
- Only affects single user/use case
- Has external fallback

---

## Related

- [docs/workload-classification.md](../../docs/workload-classification.md) - Full classification reference
- [cluster/flux/meta/priority-classes.yaml](../../cluster/flux/meta/priority-classes.yaml) - Priority class definitions
