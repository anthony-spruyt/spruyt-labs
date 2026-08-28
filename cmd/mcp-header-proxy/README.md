# mcp-header-proxy

Reverse proxy that forwards MCP headers from an HTTP request into the JSON-RPC body before passing it upstream. Deployed as a sidecar alongside n8n, whose MCP client trigger reads the values from the body rather than the headers.

Streaming responses are flushed immediately (`FlushInterval: -1`) so SSE streams are not buffered, and the write deadline is disabled for the same reason.

## Configuration

| Variable       | Default                 | Purpose                         |
| -------------- | ----------------------- | ------------------------------- |
| `LISTEN_ADDR`  | `:8080`                 | Address the proxy binds to      |
| `UPSTREAM_URL` | `http://localhost:5678` | Upstream the request is sent to |

`GET /healthz` returns `ok` and is used for probes.

## Releases

Versioning is managed by release-please. See `docs/releases.md`.
