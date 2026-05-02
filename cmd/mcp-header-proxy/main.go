package main

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
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
	upstreamRaw := envOr("UPSTREAM_URL", "http://localhost:5678")

	upstream, err := url.Parse(upstreamRaw)
	if err != nil {
		logger.Error("invalid UPSTREAM_URL", "error", err)
		return 1
	}

	logger.Info("starting mcp-header-proxy",
		"version", version,
		"commit", commit,
		"listen", listenAddr,
		"upstream", upstreamRaw,
	)

	proxy := NewProxy(upstream, logger)

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthHandler)
	mux.Handle("/", proxy)

	srv := &http.Server{
		Handler:      mux,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 0, // SSE streams have no write deadline
		IdleTimeout:  120 * time.Second,
	}

	ln, err := net.Listen("tcp", listenAddr)
	if err != nil {
		logger.Error("failed to listen", "addr", listenAddr, "error", err)
		return 1
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	go func() {
		if srvErr := srv.Serve(ln); srvErr != nil && srvErr != http.ErrServerClosed {
			logger.Error("server error", "error", srvErr)
		}
	}()

	<-ctx.Done()
	logger.Info("shutting down")
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("shutdown error", "error", err)
	}
	return 0
}

func healthHandler(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, "ok")
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
