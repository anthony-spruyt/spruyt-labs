# Crafty Controller - Minecraft Server Panel

## Overview

Web panel that lets the kids create and run Minecraft Bedrock servers and install add-ons without touching YAML. Game servers run as child processes inside the Crafty container, so there is no Docker-in-Docker. LAN only at `crafty.lan.${EXTERNAL_DOMAIN}`; console players reach it through [Bedrock Connect](../bedrock-connect/README.md).

## Operations

### Ports are fixed in advance

The `bedrock` LoadBalancer Service (IP `${CRAFTY_CONTROLLER_IP4}`) exposes UDP 19132-19139 up front, so a server created in the UI must use a port in that range to be reachable. A ninth server needs a new port added to the Service in `app/values.yaml`.

The `bedrock-tcp` Service shares that IP and exposes TCP 19132. The NetherNet server on port 19132 uses it for signaling and UDP 19132-19136 for game traffic (see Remote play), which leaves UDP 19137-19139 for other servers. Another NetherNet server needs its TCP port added to the `bedrock-tcp` Service, the container ports in `app/values.yaml` and the `allow-crafty-bedrock-ingress` policy.

### First login

The panel has no SSO. On an empty PVC, Crafty generates the `admin` password on first start and writes it to `/crafty/app/config/default-creds.txt` on the data PVC, not to a Kubernetes Secret. Read it from the pod, then change it immediately.

### Add-ons

Upload `.mcpack`/`.mcaddon` files through the server's Files view into `behavior_packs/` or `resource_packs/`, then restart that server.

### Remote play

Bedrock 26.60 clients only speak NetherNet: HTTP signaling on the TCP `server-port` and game traffic on the UDP ports in `server-udp-ports`, one UDP port per concurrent player. A NetherNet server is reachable from outside the LAN when:

- The public DNS-only record `minecraft.${EXTERNAL_DOMAIN}` exists (`infra/terraform/cloudflare/dns.tf`).
- The router forwards TCP 19132 and UDP 19132-19136 to `${CRAFTY_CONTROLLER_IP4}` on the same ports. The forwards live in UniFi, not in Git.
- `server.properties` carries the home WAN IP in `server-udp-ports`, one `server-udp-ports=<wan-ip>:<port>:<port>` line per port. Ranges and comma lists are mis-parsed (Mojira BDS-23126), and the server advertises only its own IPs otherwise (Mojira BDS-23108).

LAN players reach the server through the router's hairpin NAT. The server's allow-list is on. The Fambam server runs RakNet on UDP 19139 with LAN visibility off, because with RakNet LAN visibility binds UDP 19132 and 19133 whatever port is set.

When the home IP changes, update the `server-udp-ports` lines as well as the `home_ip` variable on the Terraform Cloud workspace (see the [Cloudflare module](../../../../infra/terraform/cloudflare/README.md)), then restart the server.

## References

- [Crafty Controller Documentation](https://docs.craftycontrol.com/)
