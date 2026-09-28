# Technitium Secondary - DNS Replica

## Overview

Second Technitium instance on its own LoadBalancer IP, so LAN and cluster DNS survive the loss of one node. Zones are replicated from the primary; configuration is not.

## Operations

Everything in the [primary README](../technitium/README.md) about PVC-persisted config applies here independently: SSO, admin password and blocking settings are configured per instance in each admin UI. It shares the primary's Authentik provider and client credentials, with its own redirect URI (`https://dns-secondary.lan.${EXTERNAL_DOMAIN}:53443/sso/callback`). An OIDC secret rotation has to be
entered here as well as on the primary.

## Troubleshooting

1. **Secondary answers differ from the primary**
   - **Cause**: Zone transfer or NOTIFY blocked, or the zone was created on the primary without being added to the catalog zone.
   - **Fix**: Check the transfer rules in `technitium/app/network-policies.yaml`, then force a transfer from the secondary's UI.
