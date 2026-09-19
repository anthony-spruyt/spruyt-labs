package traefik_api_key_auth

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func dummyHandler(code int) http.Handler {
	return http.HandlerFunc(func(rw http.ResponseWriter, _ *http.Request) {
		rw.WriteHeader(code)
	})
}

func captureHandler() (http.Handler, func() http.Header) {
	var captured http.Header
	h := http.HandlerFunc(func(_ http.ResponseWriter, req *http.Request) {
		captured = req.Header.Clone()
	})
	return h, func() http.Header { return captured }
}

func mustNew(t *testing.T, next http.Handler, config *Config) http.Handler {
	t.Helper()
	h, err := New(context.Background(), next, config, "test")
	if err != nil {
		t.Fatalf("New() error: %v", err)
	}
	return h
}

// --- Passthrough mode tests ---

func TestPassthroughMode_Creation(t *testing.T) {
	config := &Config{
		AuthenticationHeader:     true,
		AuthenticationHeaderName: "X-API-KEY",
		ForwardBearerHeader:      true,
		ForwardBearerHeaderName:  "Authorization",
		RemoveHeadersOnSuccess:   true,
	}
	h, err := New(context.Background(), dummyHandler(200), config, "test-passthrough")
	if err != nil {
		t.Fatalf("passthrough mode creation failed: %v", err)
	}
	if h == nil {
		t.Fatal("handler is nil")
	}
}

func TestPassthroughMode_CreationWithNilKeys(t *testing.T) {
	config := &Config{
		AuthenticationHeader:     true,
		AuthenticationHeaderName: "X-API-KEY",
		ForwardBearerHeader:      true,
		ForwardBearerHeaderName:  "Authorization",
		Keys:                     nil,
	}
	_, err := New(context.Background(), dummyHandler(200), config, "test-passthrough-nil")
	if err != nil {
		t.Fatalf("passthrough mode with nil keys failed: %v", err)
	}
}

func TestPassthroughMode_CreationWithEmptyKeys(t *testing.T) {
	config := &Config{
		AuthenticationHeader:     true,
		AuthenticationHeaderName: "X-API-KEY",
		ForwardBearerHeader:      true,
		ForwardBearerHeaderName:  "Authorization",
		Keys:                     []string{},
	}
	_, err := New(context.Background(), dummyHandler(200), config, "test-passthrough-empty")
	if err != nil {
		t.Fatalf("passthrough mode with empty keys failed: %v", err)
	}
}

func TestPassthroughMode_TranslatesHeader(t *testing.T) {
	backend, getHeaders := captureHandler()
	config := &Config{
		AuthenticationHeader:     true,
		AuthenticationHeaderName: "X-API-KEY",
		ForwardBearerHeader:      true,
		ForwardBearerHeaderName:  "Authorization",
		RemoveHeadersOnSuccess:   true,
	}
	h := mustNew(t, backend, config)

	req := httptest.NewRequest(http.MethodPost, "/mcp", nil)
	req.Header.Set("X-API-KEY", "tok")
	rw := httptest.NewRecorder()
	h.ServeHTTP(rw, req)

	headers := getHeaders()
	auth := headers.Get("Authorization")
	if auth != "Bearer tok" {
		t.Errorf("expected Authorization: Bearer tok, got: %q", auth)
	}
}

func TestPassthroughMode_StripsSourceHeader(t *testing.T) {
	backend, getHeaders := captureHandler()
	config := &Config{
		AuthenticationHeader:     true,
		AuthenticationHeaderName: "X-API-KEY",
		ForwardBearerHeader:      true,
		ForwardBearerHeaderName:  "Authorization",
		RemoveHeadersOnSuccess:   true,
	}
	h := mustNew(t, backend, config)

	req := httptest.NewRequest(http.MethodPost, "/mcp", nil)
	req.Header.Set("X-API-KEY", "tok")
	rw := httptest.NewRecorder()
	h.ServeHTTP(rw, req)

	headers := getHeaders()
	if v := headers.Get("X-API-KEY"); v != "" {
		t.Errorf("X-API-KEY should be stripped, got: %q", v)
	}
}

func TestPassthroughMode_KeepsSourceHeaderWhenConfigured(t *testing.T) {
	backend, getHeaders := captureHandler()
	config := &Config{
		AuthenticationHeader:     true,
		AuthenticationHeaderName: "X-API-KEY",
		ForwardBearerHeader:      true,
		ForwardBearerHeaderName:  "Authorization",
		RemoveHeadersOnSuccess:   false,
	}
	h := mustNew(t, backend, config)

	req := httptest.NewRequest(http.MethodPost, "/mcp", nil)
	req.Header.Set("X-API-KEY", "tok")
	rw := httptest.NewRecorder()
	h.ServeHTTP(rw, req)

	headers := getHeaders()
	if v := headers.Get("X-API-KEY"); v != "tok" {
		t.Errorf("X-API-KEY should be preserved, got: %q", v)
	}
}

func TestPassthroughMode_RejectsMissingHeader(t *testing.T) {
	config := &Config{
		AuthenticationHeader:     true,
		AuthenticationHeaderName: "X-API-KEY",
		ForwardBearerHeader:      true,
		ForwardBearerHeaderName:  "Authorization",
	}
	h := mustNew(t, dummyHandler(200), config)

	req := httptest.NewRequest(http.MethodPost, "/mcp", nil)
	rw := httptest.NewRecorder()
	h.ServeHTTP(rw, req)

	if rw.Code != http.StatusForbidden {
		t.Errorf("expected 403, got %d", rw.Code)
	}
}

func TestPassthroughMode_RejectsEmptyHeader(t *testing.T) {
	config := &Config{
		AuthenticationHeader:     true,
		AuthenticationHeaderName: "X-API-KEY",
		ForwardBearerHeader:      true,
		ForwardBearerHeaderName:  "Authorization",
	}
	h := mustNew(t, dummyHandler(200), config)

	req := httptest.NewRequest(http.MethodPost, "/mcp", nil)
	req.Header.Set("X-API-KEY", "")
	rw := httptest.NewRecorder()
	h.ServeHTTP(rw, req)

	if rw.Code != http.StatusForbidden {
		t.Errorf("expected 403, got %d", rw.Code)
	}
}

func TestPassthroughMode_ExemptPathSkipsAuth(t *testing.T) {
	config := &Config{
		AuthenticationHeader:     true,
		AuthenticationHeaderName: "X-API-KEY",
		ForwardBearerHeader:      true,
		ForwardBearerHeaderName:  "Authorization",
		ExemptPaths:              []string{"/health"},
	}
	h := mustNew(t, dummyHandler(200), config)

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rw := httptest.NewRecorder()
	h.ServeHTTP(rw, req)

	if rw.Code != http.StatusOK {
		t.Errorf("exempt path should return 200, got %d", rw.Code)
	}
}

func TestPassthroughMode_DefaultBearerHeaderName(t *testing.T) {
	config := &Config{
		AuthenticationHeader:     true,
		AuthenticationHeaderName: "X-API-KEY",
		ForwardBearerHeader:      true,
		ForwardBearerHeaderName:  "",
	}
	_, err := New(context.Background(), dummyHandler(200), config, "test-default-name")
	if err != nil {
		t.Fatalf("should default forwardBearerHeaderName to Authorization: %v", err)
	}
}

// --- Simulates how Traefik creates plugin config from CRD ---

func TestPassthroughMode_TraefikConfigMerge(t *testing.T) {
	// Traefik calls CreateConfig() then JSON-merges CRD values on top.
	base := CreateConfig()

	crdJSON := `{
		"authenticationHeader": true,
		"authenticationHeaderName": "X-API-KEY",
		"bearerHeader": false,
		"removeHeadersOnSuccess": true,
		"forwardBearerHeader": true,
		"forwardBearerHeaderName": "Authorization"
	}`

	if err := json.Unmarshal([]byte(crdJSON), base); err != nil {
		t.Fatalf("JSON unmarshal failed: %v", err)
	}

	if !base.ForwardBearerHeader {
		t.Fatal("ForwardBearerHeader should be true after merge")
	}

	// Keys should remain as initialized by CreateConfig (empty slice)
	if base.Keys == nil {
		t.Log("Keys is nil after merge")
	} else {
		t.Logf("Keys length: %d", len(base.Keys))
	}

	passthroughMode := base.ForwardBearerHeader && len(base.Keys) == 0
	if !passthroughMode {
		t.Fatalf("passthroughMode should be true; ForwardBearerHeader=%v, len(Keys)=%d", base.ForwardBearerHeader, len(base.Keys))
	}

	// Full New() should succeed
	backend, getHeaders := captureHandler()
	h, err := New(context.Background(), backend, base, "test-traefik-merge")
	if err != nil {
		t.Fatalf("New() failed after Traefik-style merge: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "/mcp", nil)
	req.Header.Set("X-API-KEY", "tok2")
	rw := httptest.NewRecorder()
	h.ServeHTTP(rw, req)

	headers := getHeaders()
	if auth := headers.Get("Authorization"); auth != "Bearer tok2" {
		t.Errorf("expected Authorization: Bearer tok2, got: %q", auth)
	}
}

// --- Normal mode tests (existing behavior preserved) ---

func TestNormalMode_ValidKey(t *testing.T) {
	os.Setenv("TEST_API_KEY", "testkey")
	defer os.Unsetenv("TEST_API_KEY")

	backend, getHeaders := captureHandler()
	config := &Config{
		AuthenticationHeader:     true,
		AuthenticationHeaderName: "X-API-KEY",
		BearerHeader:             false,
		Keys:                     []string{"env:TEST_API_KEY"},
		RemoveHeadersOnSuccess:   true,
	}
	h := mustNew(t, backend, config)

	req := httptest.NewRequest(http.MethodGet, "/api", nil)
	req.Header.Set("X-API-KEY", "testkey")
	rw := httptest.NewRecorder()
	h.ServeHTTP(rw, req)

	headers := getHeaders()
	if v := headers.Get("X-API-KEY"); v != "" {
		t.Errorf("X-API-KEY should be stripped, got: %q", v)
	}
}

func TestNormalMode_InvalidKey(t *testing.T) {
	os.Setenv("TEST_API_KEY", "testkey")
	defer os.Unsetenv("TEST_API_KEY")

	config := &Config{
		AuthenticationHeader:     true,
		AuthenticationHeaderName: "X-API-KEY",
		BearerHeader:             false,
		Keys:                     []string{"env:TEST_API_KEY"},
	}
	h := mustNew(t, dummyHandler(200), config)

	req := httptest.NewRequest(http.MethodGet, "/api", nil)
	req.Header.Set("X-API-KEY", "wrong-key")
	rw := httptest.NewRecorder()
	h.ServeHTTP(rw, req)

	if rw.Code != http.StatusForbidden {
		t.Errorf("expected 403, got %d", rw.Code)
	}
}

func TestNormalMode_WithForwardBearer(t *testing.T) {
	os.Setenv("TEST_API_KEY", "testkey")
	defer os.Unsetenv("TEST_API_KEY")

	backend, getHeaders := captureHandler()
	config := &Config{
		AuthenticationHeader:     true,
		AuthenticationHeaderName: "X-API-KEY",
		BearerHeader:             false,
		Keys:                     []string{"env:TEST_API_KEY"},
		RemoveHeadersOnSuccess:   true,
		ForwardBearerHeader:      true,
		ForwardBearerHeaderName:  "Authorization",
	}
	h := mustNew(t, backend, config)

	req := httptest.NewRequest(http.MethodGet, "/api", nil)
	req.Header.Set("X-API-KEY", "testkey")
	rw := httptest.NewRecorder()
	h.ServeHTTP(rw, req)

	headers := getHeaders()
	if auth := headers.Get("Authorization"); auth != "Bearer testkey" {
		t.Errorf("expected Authorization: Bearer testkey, got: %q", auth)
	}
}

func TestNormalMode_BearerAuth(t *testing.T) {
	os.Setenv("TEST_API_KEY", "testkey")
	defer os.Unsetenv("TEST_API_KEY")

	config := &Config{
		AuthenticationHeader:     false,
		BearerHeader:             true,
		BearerHeaderName:         "Authorization",
		Keys:                     []string{"env:TEST_API_KEY"},
		RemoveHeadersOnSuccess:   true,
	}
	h := mustNew(t, dummyHandler(200), config)

	req := httptest.NewRequest(http.MethodGet, "/api", nil)
	req.Header.Set("Authorization", "Bearer testkey")
	rw := httptest.NewRecorder()
	h.ServeHTTP(rw, req)

	if rw.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", rw.Code)
	}
}

func TestNormalMode_NoKeys_Fails(t *testing.T) {
	config := &Config{
		AuthenticationHeader:     true,
		AuthenticationHeaderName: "X-API-KEY",
		BearerHeader:             false,
		Keys:                     []string{},
	}
	_, err := New(context.Background(), dummyHandler(200), config, "test-no-keys")
	if err == nil {
		t.Fatal("expected error for empty keys without passthrough")
	}
}
