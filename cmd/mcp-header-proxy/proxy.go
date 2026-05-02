package main

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
)

const mcpHeaderPrefix = "x-mcp-"

// NewProxy creates a reverse proxy that intercepts tools/call JSON-RPC
// requests and injects X-MCP-* HTTP header values into params.arguments.
func NewProxy(upstream *url.URL, logger *slog.Logger) http.Handler {
	rp := &httputil.ReverseProxy{
		Rewrite: func(r *httputil.ProxyRequest) {
			r.SetURL(upstream)
			r.Out.Host = upstream.Host
		},
		FlushInterval: -1,
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			logger.Error("proxy error", "error", err, "path", r.URL.Path)
			w.WriteHeader(http.StatusBadGateway)
		},
	}

	return &proxy{rp: rp, logger: logger}
}

type proxy struct {
	rp     *httputil.ReverseProxy
	logger *slog.Logger
}

func (p *proxy) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodPost {
		mcpHeaders := extractMCPHeaders(r)
		if len(mcpHeaders) > 0 && r.Body != nil {
			body, err := io.ReadAll(r.Body)
			r.Body.Close()
			if err != nil {
				p.logger.Error("failed to read request body", "error", err)
				http.Error(w, "failed to read body", http.StatusBadGateway)
				return
			}

			modified, changed := injectHeaders(body, mcpHeaders)
			if changed {
				p.logger.Info("injected MCP headers into tools/call",
					"path", r.URL.Path,
					"headerCount", len(mcpHeaders),
					"bodyLen", len(modified),
				)
			}

			r.Body = io.NopCloser(bytes.NewReader(modified))
			r.ContentLength = int64(len(modified))
		}
	}

	p.rp.ServeHTTP(w, r)
}

func extractMCPHeaders(r *http.Request) map[string]string {
	result := make(map[string]string)
	for key, values := range r.Header {
		lower := strings.ToLower(key)
		if strings.HasPrefix(lower, mcpHeaderPrefix) && len(values) > 0 {
			result[lower] = values[0]
		}
	}
	return result
}

// injectHeaders merges MCP header values into a tools/call JSON-RPC
// request's params.arguments. Uses map[string]json.RawMessage at each
// level to preserve unknown fields.
func injectHeaders(body []byte, headers map[string]string) ([]byte, bool) {
	body = bytes.TrimSpace(body)
	if len(body) == 0 {
		return body, false
	}

	var msg map[string]json.RawMessage
	if err := json.Unmarshal(body, &msg); err != nil {
		return body, false
	}

	methodRaw, ok := msg["method"]
	if !ok {
		return body, false
	}
	var method string
	if err := json.Unmarshal(methodRaw, &method); err != nil || method != "tools/call" {
		return body, false
	}

	paramsRaw, ok := msg["params"]
	if !ok {
		return body, false
	}

	var params map[string]json.RawMessage
	if err := json.Unmarshal(paramsRaw, &params); err != nil {
		return body, false
	}

	argsRaw, hasArgs := params["arguments"]
	var args map[string]interface{}

	if hasArgs {
		if err := json.Unmarshal(argsRaw, &args); err != nil {
			return body, false
		}
	} else {
		args = make(map[string]interface{})
	}

	for k, v := range headers {
		args[k] = v
	}

	argsBytes, err := json.Marshal(args)
	if err != nil {
		return body, false
	}
	params["arguments"] = argsBytes

	paramsBytes, err := json.Marshal(params)
	if err != nil {
		return body, false
	}
	msg["params"] = paramsBytes

	modified, err := json.Marshal(msg)
	if err != nil {
		return body, false
	}

	return modified, true
}
