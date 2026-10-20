# unifi-network-mcp - UniFi Network MCP Server

## Overview

MCP server giving agents read and write access to the UniFi Network controller (clients, devices, networks, firewall policies, events), brokered through LiteLLM. Callers are limited to LiteLLM by CNP — read Operations before changing anything.

## Prerequisites

- UniFi Network controller reachable on the LAN. It runs as a container on a dedicated Raspberry Pi, **not** in this cluster, and is not managed by Flux — see the `unifi-os-upgrade` skill.
- A dedicated **local** UniFi admin account with **no MFA/2FA**. Ubiquiti Cloud SSO accounts do not work; an MFA-enabled account fails at login with `SSO MFA required but no totp_secret configured`.
- Credentials stored in `unifi-network-mcp-secrets` (SOPS). The controller address comes from the `UNIFI_IP4` substitution variable in `cluster-secrets`.

## Operations

### Access and controller port

- Endpoint registered in LiteLLM: `http://unifi-network-mcp.unifi-mcp.svc:3000/mcp`. Agents see the tools under the `mcp__litellm__unifi-*` prefix.
- UniFi OS Server publishes the UI on host `11443` mapped to container `443`; host `443` is deliberately unused, so `UNIFI_NETWORK_PORT` and the egress CNP must both say `11443`.
- No IngressRoute and no Cloudflare Tunnel route, by design (see next section).

### Access control

> **Keep `allow-litellm-ingress` as is, and do not add an IngressRoute or Cloudflare Tunnel route to this app.**

Callers are limited to LiteLLM by CNP. Agents authenticate to LiteLLM with a LiteLLM key, and LiteLLM calls the server on their behalf.

Two upstream alternatives were considered and rejected: `apps/api` (a separate REST product with API keys — not MCP, wrong shape for the LiteLLM gateway) and Ubiquiti Cloud Relay (routes network data through Ubiquiti's cloud).

#### When upgrading

On an image bump, new tools show up as drift. Compare the keys of `.module_map` in the new tag's `apps/network/src/unifi_network_mcp/tools_manifest.json` (plus `unifi_get_support_bundle` and the meta-tools named under Tool registration mode) with `allowed_tools` and `disallowed_tools` under `mcp_servers.unifi` in `cluster/apps/litellm/litellm/app/values.yaml`. Add each new tool to one of the two
lists, keep the lists disjoint, and drop entries upstream removed. Otherwise the daily drift job opens an issue.

### LiteLLM registration

The server is declared under `mcp_servers.unifi` in the LiteLLM `config.yaml` (`cluster/apps/litellm/litellm/app/values.yaml`), so a cluster rebuild restores it. Only `n8n` is still UI-managed, and LiteLLM's [README](../../litellm/README.md#mcp-servers) covers how to add a server.

Keep the entry's `server_id` and `alias`: grants reference the id and the `unifi-` tool prefix comes from the alias.

No client-side change is needed: `.mcp.json` holds a single `litellm` entry and every downstream MCP server is fanned out through it.

### Write operations are enabled

`UNIFI_POLICY_CREATE`, `UNIFI_POLICY_UPDATE` and `UNIFI_POLICY_DELETE` are all `true`; every write goes through the confirm step below.

Mutations require an explicit `confirm=true` argument — all mutating tools default to `confirm=false` and return a preview instead. `UNIFI_TOOL_PERMISSION_MODE` is pinned to `confirm` for that reason; keep it there.

The controller is covered by weekly automated cloud backups, which is the recovery path for a destructive mistake. There is no undo on the controller side.

Set any of the three policy variables to `false` to turn that verb off; narrower `UNIFI_POLICY_<SERVER>_<CATEGORY>_<ACTION>` gates (most specific wins) limit writes to chosen categories. Gates act at invocation time and do not change the tool list.

After changing any `UNIFI_POLICY_*` variable, check the startup logs for `[policy] Unrecognized env var`.

### Tool registration mode

`UNIFI_TOOL_REGISTRATION_MODE=eager` registers every tool, meta-tools included, up front. `lazy` is not used: it adds each module's tools to `tools/list` on first use, so the list changes with use and the LiteLLM drift check cannot track it.

LiteLLM exposes the domain tools directly by name, plus `unifi_get_support_bundle`, and hides tools for hardware or features this site doesn't have, plus the meta-tools (`unifi_tool_index`, `unifi_execute`, `unifi_batch`, `unifi_batch_status`). `allowed_tools` decides what agents can call and `disallowed_tools` records the tools kept off, so a tool is in exactly one of the two lists.

## Troubleshooting

1. **421 Misdirected Request / "Invalid Host header"**

   - **Symptom**: a 421 from the MCP endpoint; pod logs show `mcp.server.transport_security - WARNING - Invalid Host header: <name>`
   - **Resolution**: the Host header LiteLLM sends must appear in `UNIFI_MCP_ALLOWED_HOSTS` in `values.yaml`, **with the `:3000` port suffix**. Upstream docs say bare hostnames are normalised to `host:*`; verified against image `0.32.6` that is not true — a bare entry is rejected with 421 while the `host:3000` form is accepted. If the entry list ever needs to match an unknown port,
     `UNIFI_MCP_ENABLE_DNS_REBINDING_PROTECTION=false` disables the check entirely, but prefer listing the exact `host:port`.

2. **Connection refused despite a Ready pod**

   - **Symptom**: the service accepts nothing on 3000
   - **Resolution**: `UNIFI_MCP_HOST` must be `0.0.0.0`. The upstream default is `127.0.0.1`, which binds loopback only and is unreachable from the pod network.

3. **HTTP listener never starts, pod otherwise healthy**

   - **Symptom**: logs read `Streamable HTTP enabled in config but skipped in exec session (PID N != 1)`, then the server falls back to stdio and exits
   - **Resolution**: the app only binds HTTP when it is PID 1. Do **not** add `command:` or `args:` to the container — any wrapper shim makes the app PID 2 and the listener silently never starts. `UNIFI_MCP_HTTP_FORCE=true` overrides this but should not be needed in a pod.

4. **401 Unauthorized against the controller**

   - **Symptom**: tool calls return authentication errors
   - **Resolution**: confirm the account is a local admin with MFA disabled, and that the same credentials work in the controller web UI. Cloud SSO accounts are not supported.

5. **Container filesystem write errors**

   - **Symptom**: crash on startup writing to `$HOME` or a cache path
   - **Resolution**: the upstream image has no `USER` directive and expects to run as root. This deployment forces UID 1000 with a read-only root filesystem, so writable paths come from the `tmp` and `home` emptyDir mounts. Add a mount rather than relaxing the security context.

6. **Tool missing from the list**

   - **Symptom**: an expected tool does not appear in the LiteLLM tool list
   - **Resolution**: check whether the tool is in `disallowed_tools` under `mcp_servers.unifi` in `values.yaml`. If the site now has that hardware or feature (for example a guest network or hotspot), move it to `allowed_tools`. Policy gates never hide tools.

7. **Tool calls time out; pod logs show `Connection attempt N failed: RequestError`**

   - **Symptom**: the pod is Ready and serves MCP, but every tool call times out. Logs read `Pre-login detection inconclusive` then `RequestError`. The app logs `Tool functionality may be impaired` and serves anyway, so this does not crash-loop.
   - **Resolution**: TCP to the controller is being dropped before it arrives. The controller sits behind a zone-based firewall policy on the gateway, and the allow rule for the cluster network is **order-sensitive** — a broader block policy with a lower rule ID is evaluated first and silently drops the SYN.
   - **Rule ordering**: the allow rule must sit **above** that block. A rule in the wrong position looks correct in the UI and reports zero hits.
   - **Diagnosis**: ICMP reaching the controller while every TCP port reads `filtered` is the signature — ICMP is permitted by a separate, higher-ordered rule. Confirm with `tcpdump` on the controller host: if the SYN never arrives but the echo request does, the drop is on the gateway, not the host. Checking the rule's hit counter is faster than either.
   - Not to be confused with the controller host's own `ufw`, which permits the published UniFi ports and is **not** the cause.

## References

- [sirkirby/unifi-mcp GitHub](https://github.com/sirkirby/unifi-mcp)
- [Network server configuration](https://github.com/sirkirby/unifi-mcp/blob/main/apps/network/docs/configuration.md)
- [Transports](https://github.com/sirkirby/unifi-mcp/blob/main/apps/network/docs/transports.md)
- [Permissions](https://github.com/sirkirby/unifi-mcp/blob/main/docs/permissions.md)
