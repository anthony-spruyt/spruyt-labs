---
name: victoria-logs
description: Use when querying Kubernetes pod logs from VictoriaLogs, especially for deleted/completed pods whose logs are no longer available via kubectl. Triggers on "check logs", "pod logs", "victoria logs", "vlogs", or when investigating a dead pod's output.
---

# VictoriaLogs Query

Query Kubernetes container logs stored in VictoriaLogs. Essential for reading logs from deleted/ephemeral pods.

## Connection

```bash
kubectl exec -n observability victoria-logs-single-server-0 -- \
  wget -q -O- 'http://0.0.0.0:9428/select/logsql/query?<params>'
```

**Must use `0.0.0.0`** — `localhost` gives connection refused.

## LogsQL Query Syntax

### Field Filters

| Field | Description | Example |
|-------|-------------|---------|
| `kubernetes.pod_namespace` | Namespace | `kubernetes.pod_namespace:claude-agents-read` |
| `kubernetes.pod_name` | Pod name | `kubernetes.pod_name:claude-code-1d0f817a` |
| `kubernetes.container_name` | Container | `kubernetes.container_name:claude-code` |
| `kubernetes.pod_labels.<label>` | Pod label | `kubernetes.pod_labels.managed-by:n8n-claude-code` |
| `stream` | stdout or stderr | `stream:stderr` |
| `_msg` | Log message content | `_msg:error` |
| `_time` | Time filter | `_time:[2026-04-22T06:50:00Z,2026-04-22T07:00:00Z]` |

### Combining Filters

Use `AND` (must be uppercase) to combine:

```
kubernetes.pod_namespace:my-ns AND kubernetes.container_name:app AND _time:1h
```

### Time Filters

```
_time:1h                                          # last 1 hour
_time:30m                                         # last 30 minutes
_time:[2026-04-22T06:50:00Z,2026-04-22T07:00:00Z]  # exact range
```

### Full-Text Search

```
"connection refused"                              # exact phrase in _msg
error AND kubernetes.pod_namespace:my-ns          # word + field filter
```

## URL Encoding

These characters must be URL-encoded in wget URLs:

| Char | Encoded |
|------|---------|
| `:` | `%3A` |
| `[` | `%5B` |
| `]` | `%5D` |
| `,` | `%2C` |
| Space | `+` |

## Query Parameters

| Param | Description | Default |
|-------|-------------|---------|
| `query` | LogsQL query (required) | — |
| `limit` | Max rows returned | 1000 |
| `_time_offset` | Relative time offset | — |

## Common Queries

### Logs from a specific pod (by name)

```bash
kubectl exec -n observability victoria-logs-single-server-0 -- \
  wget -q -O- 'http://0.0.0.0:9428/select/logsql/query?query=kubernetes.pod_name%3Amy-pod+AND+_time%3A1h&limit=200'
```

### Logs from a namespace in a time range

```bash
kubectl exec -n observability victoria-logs-single-server-0 -- \
  wget -q -O- 'http://0.0.0.0:9428/select/logsql/query?query=kubernetes.pod_namespace%3Aclaude-agents-read+AND+_time%3A%5B2026-04-22T06%3A50%3A00Z%2C2026-04-22T07%3A00%3A00Z%5D&limit=100'
```

### Only stderr from a container

```bash
kubectl exec -n observability victoria-logs-single-server-0 -- \
  wget -q -O- 'http://0.0.0.0:9428/select/logsql/query?query=kubernetes.container_name%3Aclaude-code+AND+stream%3Astderr+AND+_time%3A1h&limit=100'
```

### Search for error text across all pods

```bash
kubectl exec -n observability victoria-logs-single-server-0 -- \
  wget -q -O- 'http://0.0.0.0:9428/select/logsql/query?query=%22connection+refused%22+AND+_time%3A30m&limit=50'
```

## Parsing Output

Output is newline-delimited JSON. Parse and sort by time:

```bash
| python3 -c "
import sys, json
lines = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        entry = json.loads(line)
        ts = entry.get('_time', '')
        msg = entry.get('_msg', '')
        container = entry.get('kubernetes.container_name', '')
        pod = entry.get('kubernetes.pod_name', '')
        lines.append((ts, container, pod, msg))
    except: pass
lines.sort()
for ts, c, p, msg in lines:
    print(f'{ts} [{c}@{p}] {msg[:500]}')
"
```

## Other Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/select/logsql/field_names` | List all indexed field names |
| `/select/logsql/field_values?field=<name>` | List values for a field |
| `/select/logsql/streams?query=<filter>` | List matching log streams |
| `/select/logsql/hits?query=<filter>&step=10m` | Histogram of log volume |
| `/health` | Health check |

## Gotchas

- Claude Code ephemeral pods write conversation output via K8s exec API stream, NOT to container stdout. VictoriaLogs only captures container stdout/stderr. To see Claude's actual tool calls and responses, check the n8n execution data instead.
- Init container logs are under their own `kubernetes.container_name` (e.g., `git-clone`).
- Pod logs persist in VictoriaLogs after pod deletion — this is the primary use case.
