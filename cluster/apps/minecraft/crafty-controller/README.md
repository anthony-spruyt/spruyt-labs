# Crafty Controller - Minecraft Server Panel

## Overview

Web panel that lets the kids create and run Minecraft Bedrock servers and install add-ons without touching YAML. Game servers run as child processes inside the Crafty container, so there is no Docker-in-Docker. LAN only at `crafty.lan.${EXTERNAL_DOMAIN}`; console players reach it through [Bedrock Connect](../bedrock-connect/README.md).

## Operations

### Ports are fixed in advance

The `bedrock` LoadBalancer Service (IP `${CRAFTY_CONTROLLER_IP4}`) exposes UDP 19132-19139 up front, and the servers below use all of it. A new server needs its UDP ports added to the Service in `app/values.yaml` and the UDP range in `allow-crafty-bedrock-ingress` raised to match.

The `bedrock-tcp` Service shares that IP and exposes TCP 19132 and 19139 for NetherNet signaling:

| Server  | Signaling (TCP) | Game (UDP)  | Reachable from   |
| ------- | --------------- | ----------- | ---------------- |
| Chicken | 19132           | 19132-19136 | LAN and internet |
| Fambam  | 19139           | 19137-19139 | LAN only         |

Each server's `server.properties` lists its UDP ports in `server-udp-ports`, one `<ip>:<port>:<port>` line per port, because the server advertises only its own pod IP otherwise ([BDS-23108](https://bugs.mojang.com/browse/BDS/issues/BDS-23108)). Ranges and comma lists are mis-parsed ([BDS-23126](https://bugs.mojang.com/browse/BDS/issues/BDS-23126)); switch to one range line once that is fixed.
LAN-only servers advertise `${CRAFTY_CONTROLLER_IP4}`. Keep `enable-lan-visibility=false` on all but one server, because LAN discovery binds a fixed UDP port.

Another NetherNet server needs its TCP port added to the `bedrock-tcp` Service and the `allow-crafty-bedrock-ingress` policy. Helm upgrades this release with a client-side three-way merge, which keys container ports on the number alone and drops a TCP port that shares its number with a UDP one ([kubernetes#105610](https://github.com/kubernetes/kubernetes/issues/105610)). The Service targets the
port number, so the container ports need no TCP entry. Add them if the release moves to server-side apply.

### First login

The panel has no SSO. On an empty PVC, Crafty generates the `admin` password on first start and writes it to `/crafty/app/config/default-creds.txt` on the data PVC, not to a Kubernetes Secret. Read it from the pod, then change it immediately.

### Add-ons

Upload `.mcpack`/`.mcaddon` files through the server's Files view into `behavior_packs/` or `resource_packs/`, then restart that server.

### Remote play

Bedrock 26.60 clients only speak NetherNet: HTTP signaling on the TCP `server-port` and game traffic on the UDP ports in `server-udp-ports`, one UDP port per concurrent player. A NetherNet server is reachable from outside the LAN when:

- The public DNS-only record `minecraft.${EXTERNAL_DOMAIN}` exists (`infra/terraform/cloudflare/dns.tf`).
- The router forwards TCP 19132 and UDP 19132-19136 to `${CRAFTY_CONTROLLER_IP4}` on the same ports. The forwards live in UniFi, not in Git.
- `server-udp-ports` advertises the home WAN IP instead of `${CRAFTY_CONTROLLER_IP4}`.

On the LAN the hostname resolves to `${CRAFTY_CONTROLLER_IP4}`, so signaling stays local and only the UDP game traffic loops back to the WAN IP through the router's hairpin NAT. Chicken's allow-list is on.

The [MCXboxBroadcast](../mcxboxbroadcast/README.md) bot relays joins to Chicken's TCP signaling port (its `remote-port`) through the `allow-crafty-mcxboxbroadcast-ingress` and `allow-mcxboxbroadcast-crafty-egress` policies, so moving Chicken's signaling port means updating those too.

When the home IP changes, follow the home IP steps in the [Cloudflare module README](../../../../infra/terraform/cloudflare/README.md#variables), then update the `server-udp-ports` lines and restart the server.

## References

- [Crafty Controller Documentation](https://docs.craftycontrol.com/)
