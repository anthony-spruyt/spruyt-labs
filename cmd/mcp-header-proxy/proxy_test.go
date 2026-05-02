package main

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
)

func TestExtractMCPHeaders(t *testing.T) {
	r, _ := http.NewRequest("POST", "/", nil)
	r.Header.Set("X-MCP-Job-ID", "abc123")
	r.Header.Set("X-Mcp-Session-Token", "tok456")
	r.Header.Set("Authorization", "Bearer secret")
	r.Header.Set("Content-Type", "application/json")

	got := extractMCPHeaders(r)

	if len(got) != 2 {
		t.Fatalf("expected 2 MCP headers, got %d: %v", len(got), got)
	}
	if got["x-mcp-job-id"] != "abc123" {
		t.Errorf("x-mcp-job-id = %q, want %q", got["x-mcp-job-id"], "abc123")
	}
	if got["x-mcp-session-token"] != "tok456" {
		t.Errorf("x-mcp-session-token = %q, want %q", got["x-mcp-session-token"], "tok456")
	}
}

func TestExtractMCPHeaders_None(t *testing.T) {
	r, _ := http.NewRequest("POST", "/", nil)
	r.Header.Set("Authorization", "Bearer secret")

	got := extractMCPHeaders(r)
	if len(got) != 0 {
		t.Fatalf("expected 0 MCP headers, got %d", len(got))
	}
}

func TestInjectHeaders_ToolsCall(t *testing.T) {
	body := `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"submit_result","arguments":{"status":"success"}}}`
	headers := map[string]string{
		"x-mcp-job-id":       "job-123",
		"x-mcp-session-token": "tok-456",
	}

	modified, changed := injectHeaders([]byte(body), headers)
	if !changed {
		t.Fatal("expected changed=true")
	}

	var msg map[string]json.RawMessage
	if err := json.Unmarshal(modified, &msg); err != nil {
		t.Fatal(err)
	}

	var params map[string]json.RawMessage
	json.Unmarshal(msg["params"], &params)

	var args map[string]interface{}
	json.Unmarshal(params["arguments"], &args)

	if args["x-mcp-job-id"] != "job-123" {
		t.Errorf("x-mcp-job-id = %v, want job-123", args["x-mcp-job-id"])
	}
	if args["x-mcp-session-token"] != "tok-456" {
		t.Errorf("x-mcp-session-token = %v, want tok-456", args["x-mcp-session-token"])
	}
	if args["status"] != "success" {
		t.Errorf("original arg status = %v, want success", args["status"])
	}
}

func TestInjectHeaders_OverwritesExisting(t *testing.T) {
	body := `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"submit_result","arguments":{"x-mcp-job-id":"hallucinated","status":"ok"}}}`
	headers := map[string]string{
		"x-mcp-job-id": "real-id",
	}

	modified, changed := injectHeaders([]byte(body), headers)
	if !changed {
		t.Fatal("expected changed=true")
	}

	var msg map[string]json.RawMessage
	json.Unmarshal(modified, &msg)
	var params map[string]json.RawMessage
	json.Unmarshal(msg["params"], &params)
	var args map[string]interface{}
	json.Unmarshal(params["arguments"], &args)

	if args["x-mcp-job-id"] != "real-id" {
		t.Errorf("x-mcp-job-id = %v, want real-id (should overwrite hallucinated)", args["x-mcp-job-id"])
	}
	if args["status"] != "ok" {
		t.Errorf("status = %v, want ok", args["status"])
	}
}

func TestInjectHeaders_NoArguments(t *testing.T) {
	body := `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_tools"}}`
	headers := map[string]string{"x-mcp-job-id": "job-1"}

	modified, changed := injectHeaders([]byte(body), headers)
	if !changed {
		t.Fatal("expected changed=true")
	}

	var msg map[string]json.RawMessage
	json.Unmarshal(modified, &msg)
	var params map[string]json.RawMessage
	json.Unmarshal(msg["params"], &params)
	var args map[string]interface{}
	json.Unmarshal(params["arguments"], &args)

	if args["x-mcp-job-id"] != "job-1" {
		t.Errorf("x-mcp-job-id = %v, want job-1", args["x-mcp-job-id"])
	}
}

func TestInjectHeaders_NotToolsCall(t *testing.T) {
	body := `{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}`
	headers := map[string]string{"x-mcp-job-id": "job-1"}

	_, changed := injectHeaders([]byte(body), headers)
	if changed {
		t.Fatal("expected changed=false for tools/list")
	}
}

func TestInjectHeaders_Initialize(t *testing.T) {
	body := `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}`
	headers := map[string]string{"x-mcp-job-id": "job-1"}

	_, changed := injectHeaders([]byte(body), headers)
	if changed {
		t.Fatal("expected changed=false for initialize")
	}
}

func TestInjectHeaders_InvalidJSON(t *testing.T) {
	body := `not json`
	headers := map[string]string{"x-mcp-job-id": "job-1"}

	result, changed := injectHeaders([]byte(body), headers)
	if changed {
		t.Fatal("expected changed=false for invalid JSON")
	}
	if string(result) != body {
		t.Errorf("body should be unchanged")
	}
}

func TestInjectHeaders_PreservesUnknownFields(t *testing.T) {
	body := `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"test","arguments":{"a":"b"},"_meta":{"token":"x"}}}`
	headers := map[string]string{"x-mcp-job-id": "j1"}

	modified, changed := injectHeaders([]byte(body), headers)
	if !changed {
		t.Fatal("expected changed=true")
	}

	var msg map[string]json.RawMessage
	json.Unmarshal(modified, &msg)
	var params map[string]json.RawMessage
	json.Unmarshal(msg["params"], &params)

	if _, ok := params["_meta"]; !ok {
		t.Error("_meta field lost during injection")
	}
	if _, ok := params["name"]; !ok {
		t.Error("name field lost during injection")
	}
}

func TestProxy_Integration(t *testing.T) {
	var receivedBody []byte
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedBody, _ = io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":{}}`))
	}))
	defer upstream.Close()

	upstreamURL, _ := url.Parse(upstream.URL)
	logger := slog.New(slog.NewJSONHandler(io.Discard, nil))
	p := NewProxy(upstreamURL, logger)

	body := `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"submit_result","arguments":{"status":"done"}}}`
	req := httptest.NewRequest("POST", "/mcp/agent-platform", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-MCP-Job-ID", "real-job-123")
	req.Header.Set("Authorization", "Bearer token")

	w := httptest.NewRecorder()
	p.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}

	var msg map[string]json.RawMessage
	json.Unmarshal(receivedBody, &msg)
	var params map[string]json.RawMessage
	json.Unmarshal(msg["params"], &params)
	var args map[string]interface{}
	json.Unmarshal(params["arguments"], &args)

	if args["x-mcp-job-id"] != "real-job-123" {
		t.Errorf("upstream got x-mcp-job-id = %v, want real-job-123", args["x-mcp-job-id"])
	}
	if args["status"] != "done" {
		t.Errorf("upstream got status = %v, want done", args["status"])
	}
}

func TestProxy_GETPassthrough(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Write([]byte("data: test\n\n"))
	}))
	defer upstream.Close()

	upstreamURL, _ := url.Parse(upstream.URL)
	logger := slog.New(slog.NewJSONHandler(io.Discard, nil))
	p := NewProxy(upstreamURL, logger)

	req := httptest.NewRequest("GET", "/mcp/agent-platform", nil)
	req.Header.Set("X-MCP-Job-ID", "ignored")

	w := httptest.NewRecorder()
	p.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
}

func TestProxy_NoMCPHeaders(t *testing.T) {
	var receivedBody []byte
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedBody, _ = io.ReadAll(r.Body)
		w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":{}}`))
	}))
	defer upstream.Close()

	upstreamURL, _ := url.Parse(upstream.URL)
	logger := slog.New(slog.NewJSONHandler(io.Discard, nil))
	p := NewProxy(upstreamURL, logger)

	body := `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"test","arguments":{"a":"b"}}}`
	req := httptest.NewRequest("POST", "/mcp/agent-platform", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")

	w := httptest.NewRecorder()
	p.ServeHTTP(w, req)

	if string(receivedBody) != body {
		t.Errorf("body should be unchanged when no MCP headers present")
	}
}
