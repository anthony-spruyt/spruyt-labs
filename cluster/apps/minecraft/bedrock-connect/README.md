# Bedrock Connect - Console Server List

## Overview

Lets Minecraft Bedrock players on consoles (Xbox, PlayStation, Switch), which can only join Mojang's featured servers, reach the household's self-hosted server. Consoles are tricked into connecting here, and Bedrock Connect shows a custom server list from `custom_servers.json` in `app/values.yaml`.

## Prerequisites

- DNS overrides on the LAN resolver that point the featured-server hostnames at this service's LoadBalancer IP (`${BEDROCK_CONNECT_IP4}`). They are not managed in this repo; without them consoles never reach Bedrock Connect. The hostname list is in the upstream README.
- A DNS record for `minecraft.${EXTERNAL_DOMAIN}`, the address in the custom server list. Also not managed here.

## References

- [BedrockConnect](https://github.com/Pugmatt/BedrockConnect)
