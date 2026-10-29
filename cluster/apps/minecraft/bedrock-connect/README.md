# Bedrock Connect - Console Server List

## Overview

Lets Minecraft Bedrock players on consoles (Xbox, PlayStation, Switch), which can only join Mojang's featured servers, reach the household's self-hosted server. Consoles are tricked into connecting here, and Bedrock Connect shows a custom server list from `custom_servers.json` in `app/values.yaml`.

## Prerequisites

- DNS overrides on the LAN resolver that point the featured-server hostnames at this service's LoadBalancer IP (`${BEDROCK_CONNECT_IP4}`). They are not managed in this repo; without them consoles never reach Bedrock Connect. The hostname list is in the upstream README.
- A DNS record for `minecraft.${EXTERNAL_DOMAIN}`, the address in the custom server list. Also not managed here.

## Operations

Bedrock 26.60 clients no longer speak RakNet, so Bedrock Connect serves them over NetherNet (upstream's default `net_mode`).

- NetherNet needs TCP and UDP 19132 on the LoadBalancer and the `allow-bedrock-connect-game-ingress` policy: TCP carries signaling, UDP carries the game traffic.
- `/tmp` is a writable `emptyDir`; the WebRTC native library unpacks there and the root filesystem is read-only.
- `advertise_addresses` in `app/values.yaml` is the LoadBalancer IP (`${BEDROCK_CONNECT_IP4}`) and `stun_discovery` is off. Otherwise the server advertises its WAN address, which LAN consoles cannot use.
- `identity.pem` lives on the `bedrock-connect-nethernet` PVC. Clients pin its public key, so deleting the file or the PVC makes every player confirm the server again. The PVC is labelled for Velero backup.
- The Deployment uses `Recreate` because the ReadWriteOnce volume attaches to one node only, so a rolling update whose new pod lands on another node would hang.

## References

- [BedrockConnect](https://github.com/Pugmatt/BedrockConnect)
