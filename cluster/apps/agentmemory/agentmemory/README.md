# AgentMemory - Persistent Memory for AI Coding Agents

## Overview

Persistent memory system for AI agents using triple-index search (BM25 + vector + knowledge graph). Runs as a sidecar pair: iii-engine (state/queue/stream) + Node.js worker (npx agentmemory). Low-priority workload.

## Prerequisites

- Authentik (outpost deployment + SSO blueprint)

## Operations

### Architecture

Four containers share the pod network:

| Container    | Image                   | Ports                                  | Purpose                                                         |
| ------------ | ----------------------- | -------------------------------------- | --------------------------------------------------------------- |
| engine       | `iiidev/iii:0.11.2`     | 3111 (HTTP), 3112 (WS), 9464 (metrics) | State store, queue, pub/sub, streaming                          |
| console      | `iiidev/iii:0.11.2`     | 3114 (HTTP)                            | iii Console — KV browser, OTEL traces, engine dashboard         |
| viewer-proxy | `alpine/socat`          | 3116 (viewer)                          | Forwards 0.0.0.0:3116 → 127.0.0.1:3113 (viewer binds localhost) |
| worker       | `node:20-bookworm-slim` | 3113 (viewer, localhost only)          | AgentMemory MCP + viewer via npx                                |

Worker connects to engine via `ws://localhost:49134`. Engine stores data at `/data` (Ceph block PVC).

### Access Patterns

| Consumer           | Endpoint                                     | Auth            | Ports      |
| ------------------ | -------------------------------------------- | --------------- | ---------- |
| Browser (viewer)   | `agentmemory.lan.${EXTERNAL_DOMAIN}`         | Authentik SSO   | 3116       |
| Browser (console)  | `agentmemory-console.lan.${EXTERNAL_DOMAIN}` | Authentik SSO   | 3114       |
| MCP clients (REST) | `agentmemory-mcp.lan.${EXTERNAL_DOMAIN}`     | Traefik API key | 3111       |
| Claude agents      | Pod-to-pod                                   | CNP allow-list  | 3111, 3112 |
| Coder workspaces   | Pod-to-pod                                   | CNP allow-list  | 3111, 3112 |
| n8n                | Pod-to-pod                                   | CNP allow-list  | 3111, 3112 |

### Version Pinning

Engine pinned to `iiidev/iii:0.11.2` — v0.11.6+ breaks agentmemory. Track upstream fix before upgrading.

### MCP Tools

`AGENTMEMORY_TOOLS=core` exposes 8 tools: memory_save, memory_recall, memory_smart_search, memory_consolidate, memory_sessions, memory_diagnose, memory_lesson_save, memory_reflect.

## Troubleshooting

1. **Worker CrashLoopBackOff on first deploy**

   - **Symptom**: npx download times out or OOM during install
   - **Resolution**: npm-registry-egress CNP must allow `registry.npmjs.org:443`. Check worker memory limit (512Mi) is sufficient for npx install.

1. **Viewer loads but API calls fail**

   - **Symptom**: Browser shows viewer UI but searches return errors
   - **Resolution**: Viewer proxies API calls internally. Verify engine container is healthy on port 3111. Check `III_ENGINE_URL=ws://localhost:49134` env var.

1. **Outpost not deploying**

   - **Symptom**: No `ak-outpost-agentmemory-outpost` pod in namespace
   - **Resolution**: Verify Authentik blueprint applied (`kubectl logs -n authentik-system` for blueprint errors). Check RBAC role in agentmemory namespace grants authentik SA permissions.

## References

- [AgentMemory GitHub](https://github.com/rohitg00/agentmemory)
- [iii-engine](https://github.com/iiidev-project/iii)
- [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts)
