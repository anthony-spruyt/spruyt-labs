# Crafty Controller - Minecraft Server Panel

## Overview

Web panel that lets the kids create and run Minecraft Bedrock servers and install add-ons without touching YAML. Game servers run as child processes inside the Crafty container, so there is no Docker-in-Docker. LAN only at `crafty.lan.${EXTERNAL_DOMAIN}`; console players reach it through [Bedrock Connect](../bedrock-connect/README.md).

## Operations

### Ports are fixed in advance

The `bedrock` LoadBalancer Service (IP `${CRAFTY_CONTROLLER_IP4}`) exposes UDP 19132-19139 up front, so a server created in the UI must use a port in that range to be reachable. A ninth server needs a new port added to the Service in `app/values.yaml`.

### First login

The panel has no SSO. On an empty PVC, Crafty generates the `admin` password on first start and writes it to `/crafty/app/config/default-creds.txt` on the data PVC, not to a Kubernetes Secret. Read it from the pod, then change it immediately.

### Add-ons

Upload `.mcpack`/`.mcaddon` files through the server's Files view into `behavior_packs/` or `resource_packs/`, then restart that server.

## References

- [Crafty Controller Documentation](https://docs.craftycontrol.com/)
