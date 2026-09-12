# unifi-network-mcp - UniFi Network MCP Server

## Overview

MCP (Model Context Protocol) server giving AI assistants read access to the UniFi Network controller — clients, devices, networks, firewall policies, events. Runs in streamable-HTTP transport mode as a low-priority workload, reachable only from the `litellm` namespace.

## Prerequisites

- UniFi Network controller reachable on the LAN. It runs as a container on a dedicated Raspberry Pi, **not** in this cluster, and is not managed by Flux — see the `unifi-os-upgrade` skill.
- A dedicated **local** UniFi admin account with **no MFA/2FA**. Ubiquiti Cloud SSO accounts do not work; an MFA-enabled account fails at login with `SSO MFA required but no totp_secret configured`.
- Credentials stored in `unifi-network-mcp-secrets` (SOPS). The controller address comes from the `UNIFI_IP4` substitution variable in `cluster-secrets`.

## Access

- **In-cluster only**: `http://unifi-network-mcp.unifi-mcp.svc:3000/mcp`
- **Via agents**: brokered by LiteLLM; tools surface under the `mcp__litellm__unifi-*` prefix
- **Network policies**: ingress from the `litellm` namespace only; egress restricted to the single controller address (`${UNIFI_IP4}/32`) on port 11443. UniFi OS Server publishes the UI on host `11443` mapped to container `443`; host `443` is deliberately unused, so `UNIFI_NETWORK_PORT` and the egress policy must both say `11443`.
- No IngressRoute and no Cloudflare Tunnel route — the listener has **no caller authentication** of its own, so the CiliumNetworkPolicy is the security boundary

## Operations

### No inbound authentication — the CiliumNetworkPolicy is the only boundary

> **Do not relax `allow-litellm-ingress`, and do not add an IngressRoute or Cloudflare Tunnel route to this app.** Anything that can reach port 3000 gets the full read surface of the UniFi controller with no credential at all.

This is a **gap in the upstream server**, not a missing setting on our side. Verified against image `0.32.6`: an MCP `initialize` + `tools/list` over plain HTTP with no token, no key and no `Authorization` header returns `HTTP 200`.

The FastMCP SDK underneath *does* support authentication (token verifiers, OAuth providers). This project never wires one up. The single HTTP entry point is `run_http()` in `packages/unifi-mcp-shared/src/unifi_mcp_shared/transport.py`, which calls:

```python
await server.run_streamable_http_async(
    host=host,
    port=port,
    transport_security=getattr(server, "transport_security", None),
)
```

Three arguments — no `auth=`, no `token_verifier=`, no middleware hook. There is no environment variable to enable one; `UNIFI_MCP_*`, `UNIFI_POLICY_*` and `UNIFI_NETWORK_*` contain nothing of the kind. Upstream states it directly: *"MCP HTTP has no built-in caller authentication"* and *"An allowed hostname does not replace authentication."*

What the adjacent settings actually do — none of them authenticate a caller:

| Setting                   | Purpose                                  | Authenticates caller?                |
| ------------------------- | ---------------------------------------- | ------------------------------------ |
| `UNIFI_MCP_ALLOWED_HOSTS` | `Host` header check (anti-DNS-rebinding) | No — the header is caller-controlled |
| `UNIFI_NETWORK_PASSWORD`  | Login **to the UniFi controller**        | No — outbound credential             |
| `UNIFI_POLICY_*`          | Blocks mutating tools                    | No — limits blast radius only        |

Caller identity is enforced one layer up: agents authenticate to **LiteLLM** with a LiteLLM key, and LiteLLM makes the unauthenticated in-cluster call on their behalf. Note this differs from `n8n-mcp-server` in this repo, which *does* support a real bearer token via `AUTH_TOKEN` — do not assume a matching variable exists here.

Two upstream alternatives were considered and rejected: `apps/api` (a separate REST product with API keys — not MCP, wrong shape for the LiteLLM gateway) and Ubiquiti Cloud Relay (routes network data through Ubiquiti's cloud).

#### When upgrading: check whether upstream added auth

**On every version bump, check whether upstream has added inbound authentication — and if so, wire it up and tighten this deployment.** Renovate will not flag this; it is a capability gain, not a breaking change, so it will pass silently in a routine image-tag PR.

How to check on a new tag:

1. Re-read `run_http()` in `packages/unifi-mcp-shared/src/unifi_mcp_shared/transport.py`. If `run_streamable_http_async` gained an `auth=`, `token_verifier=` or middleware argument, support has landed.
2. Grep the release notes and `apps/network/docs/transports.md` for `auth`, `bearer`, `token`.

If it has landed: add the credential to `unifi-network-mcp-secrets`, set the corresponding env var in `values.yaml`, configure the matching header on the LiteLLM MCP server entry, and update this section. Keep the CNP as defence in depth — do not widen it just because auth now exists.

### LiteLLM registration is manual

MCP servers are registered through the **LiteLLM UI**, not `config.yaml`. This deviates from the repo's declarative-only rule. YAML-side MCP config was unreliable when the other MCP servers were added; LiteLLM runs with `store_model_in_db: true` and `supported_db_objects: [mcp]`, so UI registration persists in Postgres.

**On a cluster rebuild this registration does not come back on its own** — re-add the server in the LiteLLM UI pointing at `http://unifi-network-mcp.unifi-mcp.svc:3000/mcp`.

No client-side change is needed: `.mcp.json` holds a single `litellm` entry and every downstream MCP server is fanned out through it.

### Write operations are gated off

`UNIFI_POLICY_CREATE`, `UNIFI_POLICY_UPDATE` and `UNIFI_POLICY_DELETE` are all `false`, making this a read-only deployment. Gates block execution at invocation time; they do **not** hide tools from the tool list, so an agent can still see mutating tools and will get a refusal naming the variable to flip.

A **typo in a policy variable name fails open** — the gate silently does not apply. After changing any `UNIFI_POLICY_*` value, check the startup logs for `[policy] Unrecognized env var`.

### Tool registration mode

`UNIFI_TOOL_REGISTRATION_MODE=lazy` registers six meta-tools (`unifi_tool_index`, `unifi_execute`, `unifi_batch`, `unifi_batch_status`, `unifi_load_tools`, `unifi_get_support_bundle`) and loads the ~194-tool catalog on demand. Setting `eager` would register all of them up front — a large surface to push through the gateway.

## Troubleshooting

1. **403 Forbidden / "host not allowed"**

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

   - **Symptom**: an expected tool does not appear
   - **Resolution**: expected in `lazy` mode — use `unifi_tool_index` then `unifi_execute`. Policy gates never hide tools.

7. **Tool calls time out; pod logs show `Connection attempt N failed: RequestError`**

   - **Symptom**: the pod is Ready and serves MCP, but every tool call times out. Logs read `Pre-login detection inconclusive` then `RequestError`. The app logs `Tool functionality may be impaired` and serves anyway, so this does not crash-loop.
   - **Resolution**: TCP to the controller is being dropped before it arrives. The controller sits behind a zone-based firewall policy on the gateway, and the allow rule for the cluster network is **order-sensitive** — a broader block policy with a lower rule ID is evaluated first and silently drops the SYN.
   - **Rule ordering**: the allow rule must sit **above** that block. A rule in the wrong position looks correct in the UI and reports zero hits.
   - **Diagnosis**: ICMP reaching the controller while every TCP port reads `filtered` is the signature — ICMP is permitted by a separate, higher-ordered rule. Confirm with `tcpdump` on the controller host: if the SYN never arrives but the echo request does, the drop is on the gateway, not the host. Checking the rule's hit counter is faster than either.
   - Not to be confused with the controller host's own `ufw`, which allows all published UniFi ports from any source and is **not** the cause.

## References

- [sirkirby/unifi-mcp GitHub](https://github.com/sirkirby/unifi-mcp)
- [Network server configuration](https://github.com/sirkirby/unifi-mcp/blob/main/apps/network/docs/configuration.md)
- [Transports](https://github.com/sirkirby/unifi-mcp/blob/main/apps/network/docs/transports.md)
- [Permissions](https://github.com/sirkirby/unifi-mcp/blob/main/docs/permissions.md)
- [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts)
