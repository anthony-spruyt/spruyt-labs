package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
)

var (
	version = "dev"
	commit  = "unknown"
)

func main() {
	os.Exit(run())
}

func run() int {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	listenAddr := envOr("LISTEN_ADDR", ":8080")
	llmGuardURL := envOr("LLM_GUARD_URL", "http://localhost:8000")
	threshold := envOrFloat("INJECTION_THRESHOLD", 0.5)

	logger.Info("starting llm-guard-adapter",
		"version", version,
		"commit", commit,
		"listen", listenAddr,
		"llm_guard_url", llmGuardURL,
		"injection_threshold", threshold,
	)

	client := &http.Client{Timeout: 30 * time.Second}
	handler := &adapter{
		client:      client,
		llmGuardURL: llmGuardURL,
		threshold:   threshold,
		logger:      logger,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthHandler)
	mux.Handle("/", handler)

	srv := &http.Server{
		Addr:              listenAddr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("server failed", "error", err)
			stop()
		}
	}()

	<-ctx.Done()
	logger.Info("shutting down")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("shutdown error", "error", err)
		return 1
	}
	return 0
}

type litellmRequest struct {
	Texts              []string          `json:"texts"`
	StructuredMessages []structuredMsg   `json:"structured_messages"`
	InputType          string            `json:"input_type"`
	CallID             string            `json:"litellm_call_id"`
	TraceID            string            `json:"litellm_trace_id"`
}

type structuredMsg struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type litellmResponse struct {
	Action        string `json:"action"`
	BlockedReason string `json:"blocked_reason,omitempty"`
}

type llmGuardRequest struct {
	Prompt string `json:"prompt"`
}

type llmGuardResponse struct {
	SanitizedPrompt string             `json:"sanitized_prompt"`
	IsValid         bool               `json:"is_valid"`
	Scanners        map[string]float64 `json:"scanners"`
}

type adapter struct {
	client      *http.Client
	llmGuardURL string
	threshold   float64
	logger      *slog.Logger
}

func (a *adapter) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, 10<<20)) // 10MB limit
	if err != nil {
		a.logger.Error("read body failed", "error", err)
		a.respond(w, "NONE", "")
		return
	}

	var req litellmRequest
	if err := json.Unmarshal(body, &req); err != nil {
		a.logger.Error("parse request failed", "error", err)
		a.respond(w, "NONE", "")
		return
	}

	prompt := a.extractPrompt(req)
	if prompt == "" {
		a.respond(w, "NONE", "")
		return
	}

	guardResp, err := a.scanPrompt(r.Context(), prompt)
	if err != nil {
		a.logger.Error("llm-guard scan failed", "error", err, "call_id", req.CallID)
		a.respond(w, "NONE", "")
		return
	}

	a.logger.Info("scan complete",
		"call_id", req.CallID,
		"is_valid", guardResp.IsValid,
		"scanners", guardResp.Scanners,
	)

	if !guardResp.IsValid {
		reasons := a.buildBlockReason(guardResp.Scanners)
		a.respond(w, "BLOCKED", reasons)
		return
	}

	a.respond(w, "NONE", "")
}

func (a *adapter) extractPrompt(req litellmRequest) string {
	if len(req.Texts) > 0 {
		return strings.Join(req.Texts, "\n")
	}
	var parts []string
	for _, msg := range req.StructuredMessages {
		if msg.Role == "user" {
			parts = append(parts, msg.Content)
		}
	}
	return strings.Join(parts, "\n")
}

func (a *adapter) scanPrompt(ctx context.Context, prompt string) (*llmGuardResponse, error) {
	guardReq := llmGuardRequest{Prompt: prompt}
	payload, err := json.Marshal(guardReq)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, a.llmGuardURL+"/analyze/prompt", bytes.NewReader(payload))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := a.client.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("http request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return nil, fmt.Errorf("llm-guard returned %d: %s", resp.StatusCode, string(respBody))
	}

	var guardResp llmGuardResponse
	if err := json.NewDecoder(resp.Body).Decode(&guardResp); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	return &guardResp, nil
}

func (a *adapter) buildBlockReason(scanners map[string]float64) string {
	var reasons []string
	for name, score := range scanners {
		if score >= a.threshold {
			reasons = append(reasons, fmt.Sprintf("%s (score: %.2f)", name, score))
		}
	}
	if len(reasons) == 0 {
		return "content flagged by LLM Guard"
	}
	return "blocked by: " + strings.Join(reasons, ", ")
}

func (a *adapter) respond(w http.ResponseWriter, action, reason string) {
	resp := litellmResponse{Action: action, BlockedReason: reason}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func healthHandler(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envOrFloat(key string, fallback float64) float64 {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	var f float64
	if _, err := fmt.Sscanf(v, "%f", &f); err != nil {
		return fallback
	}
	return f
}
