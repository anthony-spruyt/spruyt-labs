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

Versioning is managed by release-please. A push to `main` that touches this directory updates a release pull request; merging it creates the tag and a draft release, which triggers the image build. The release is published once the image has been pushed, so a published release always has an image behind it.

Commit types drive the version: `feat` bumps the minor, `feat!` or a `BREAKING CHANGE` footer bumps the major, and anything else bumps the patch. A `Release-As: X.Y.Z` footer overrides the computed version.
