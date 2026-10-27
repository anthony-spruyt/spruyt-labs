# Discovery

Commands for cluster topology, schematics and versions, plus the node lookups Phase 3 uses (Step 3.1 and Step 3.4).

## Cluster Topology Discovery

Discover node IPs at runtime rather than hardcoding them; they are kept out of the repo and can change:

```bash
kubectl get nodes -o wide
kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'
kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'
```

```bash
# Get talosctl endpoints
talosctl config info

# Get cluster VIP endpoint
talosctl config info | grep -i endpoint
```

## Schematic Discovery

Get schematics from live nodes, not from documentation or `topf.yaml` (which may be outdated).

```bash
# Get schematic ID from a running node (most reliable)
talosctl get extensions -n <node-ip> 2>/dev/null | grep schematic

# Get control plane schematic (from any CP node)
CP_IP=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
CP_SCHEMATIC=$(talosctl get extensions -n $CP_IP 2>/dev/null | grep schematic | awk '{print $NF}')

# Get worker schematic (from any worker node)
WORKER_IP=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
WORKER_SCHEMATIC=$(talosctl get extensions -n $WORKER_IP 2>/dev/null | grep schematic | awk '{print $NF}')

# Fallback: resolve one hardware class at a time from its schematic definition.
# `task talos:schematic-ids` prints the whole set sorted and unlabelled, so it cannot
# tell you which ID belongs to which class. talos/topf.yaml maps node -> schematic file.
curl -sX POST --data-binary @talos/schematics/e2.yaml https://factory.talos.dev/schematics
curl -sX POST --data-binary @talos/schematics/ms-01.yaml https://factory.talos.dev/schematics
```

**Why live nodes?** Documentation and `talos/schematics/` may reference old schematics. The running node always has the correct schematic ID for that hardware class.

## Version Detection

Detect current and target versions:

```bash
# Current version in topf.yaml
grep "^talosVersion:" talos/topf.yaml

# Running version on nodes
talosctl version --nodes <node-ip> --short

# If PR provided, read PR diff and grep for talosVersion
```

## Step 3.1: Control plane node info

```bash
# Get control plane node IPs
CP_NODES=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')

# Get cluster endpoint
ENDPOINT=$(talosctl config info | grep -i endpoint | awk '{print $2}')

# Get schematic from the live control plane node (see Schematic Discovery)
SCHEMATIC=$(talosctl get extensions -n "${CP_IP}" 2>/dev/null | grep schematic | awk '{print $NF}')
```

## Step 3.4: Node name from IP

Sets `NODE_NAME` for the `kubectl wait` in Step 3.4:

```bash
NODE_NAME=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' | awk -v ip="<node-ip>" '$2==ip {print $1}')
```
