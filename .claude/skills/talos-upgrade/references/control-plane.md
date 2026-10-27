# Phase 2 and Phase 3: etcd Backup and Control Plane Upgrades

Commands and detail for Phase 2 and Steps 3.1 to 3.6. The gates are in the skill.

## Phase 2: etcd backup

Take this before any control plane upgrade:

```bash
CP_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

SNAPSHOT=/tmp/etcd-backup-$(date +%Y%m%d-%H%M%S).snapshot

# Streams the snapshot to this machine, not to the node
talosctl -n $CP_NODE etcd snapshot "$SNAPSHOT"
ls -l "$SNAPSHOT"
```

Post backup confirmation, with the local snapshot path, to the issue.

## Step 3.1: Get node info

Get the schematic from the live control plane node, as in [Schematic Discovery](discovery.md#schematic-discovery):

```bash
# Get control plane node IPs
CP_NODES=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')

# Get cluster endpoint
ENDPOINT=$(talosctl config info | grep -i endpoint | awk '{print $2}')

# Get schematic from the live control plane node (see Schematic Discovery)
SCHEMATIC=$(talosctl get extensions -n "${CP_IP}" 2>/dev/null | grep schematic | awk '{print $NF}')
```

## Step 3.2: Pre-node health check

```bash
# Verify etcd quorum before proceeding
# CP nodes only; workers answer etcd calls with "Unimplemented"
talosctl etcd status -n <cp-ip-1>,<cp-ip-2>,<cp-ip-3>
# Must show 3 healthy members
```

## Step 3.3: Execute upgrade

```bash
# IMPORTANT: For CP upgrades, use a SURVIVING CP node as endpoint, NOT the cluster VIP.
# The VIP may route to the node being upgraded, causing the command to lose connection.
# Choose an endpoint that is NOT the node being upgraded.
talosctl upgrade \
  --nodes <node-ip> \
  --endpoints <surviving-cp-ip> \
  --image factory.talos.dev/metal-installer-secureboot/<schematic>:<target-version>
```

**Endpoint selection for control plane upgrades:**

| Node Being Upgraded | Use as Endpoint                |
| ------------------- | ------------------------------ |
| 1st CP node         | 2nd CP node                    |
| 2nd CP node         | 1st CP node (already upgraded) |
| 3rd CP node         | 1st CP node (already upgraded) |

## Step 3.4: Wait for node recovery

```bash
# Wait for node to become Ready (timeout: 5 minutes)
NODE_NAME=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' | awk -v ip="<node-ip>" '$2==ip {print $1}')
kubectl wait --for=condition=Ready node/$NODE_NAME --timeout=300s

# Verify Talos API is responsive
talosctl health -n <node-ip>

# Verify etcd quorum restored (must show 3 healthy)
# Target only CP nodes
talosctl etcd status -n <cp-ip-1>,<cp-ip-2>,<cp-ip-3>
```

**Expect the raft term to advance by 1 when you upgrade the node currently holding the leader lease.** Rebooting the leader triggers exactly one leader election. This is normal and benign.

What actually matters, and what you should verify:

- All 3 members respond
- `RAFT INDEX` is consistent across members (they may differ by a few as writes land)
- The `ERRORS` column is empty
- The term is **stable** afterwards — a term that keeps climbing across checks means flapping, which IS a problem worth stopping for

## Step 3.5: Post-node validation

```bash
# Verify version upgraded
talosctl version --nodes <node-ip> --short
```

## Step 3.6: Post progress to issue

Post progress to the issue after each node, with node names only ([templates.md](templates.md), "Progress comment").

**WAIT between each control plane node:**

- Minimum 60 seconds after node Ready
- etcd quorum must show 3 healthy members
- Node must be fully Ready
