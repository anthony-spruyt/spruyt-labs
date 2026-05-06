# Technitium Secondary - DNS Server Replica

## Overview

Technitium Secondary is a replica DNS server that provides redundant DNS services and load balancing. Works in conjunction with the primary Technitium DNS server to ensure high availability for DNS resolution.

## Prerequisites

- Primary Technitium DNS server deployed
- Persistent storage for DNS zone data
- Authentik OIDC SSO configured (see primary README for details)

## Single Sign-On (SSO)

SSO configuration is shared with the primary instance. See the [primary Technitium README](../technitium/README.md#single-sign-on-sso) for full details.

Key differences for secondary:

- Redirect URI: `https://dns-secondary.lan.${EXTERNAL_DOMAIN}:53443/sso/callback`
- SSO must be configured separately via this instance's admin UI
- Same client ID and client secret as primary

## Troubleshooting

1. **Zone synchronization failures**

   - **Symptom**: Secondary not receiving zone updates
   - **Resolution**: Check zone transfer settings and network connectivity between primary and secondary

1. **DNS resolution inconsistencies**

   - **Symptom**: Different responses from primary and secondary
   - **Resolution**: Force zone transfer via web UI and verify consistency

## References

- [Technitium Documentation](https://technitium.com/dns/)
