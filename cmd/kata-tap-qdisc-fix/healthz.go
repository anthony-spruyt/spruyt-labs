package main

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"sync/atomic"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type readyState struct{ ready atomic.Bool }

func (r *readyState) markReady()    { r.ready.Store(true) }
func (r *readyState) isReady() bool { return r.ready.Load() }

// startHealthServer listens on healthPort for /healthz and /readyz. Returns
// a shutdown func callers should defer.
func startHealthServer(healthPort int, state *readyState, logger *slog.Logger) func() {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200); _, _ = w.Write([]byte("ok")) })
	mux.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) {
		if !state.isReady() {
			w.WriteHeader(503)
			_, _ = w.Write([]byte("not ready"))
			return
		}
		w.WriteHeader(200)
		_, _ = w.Write([]byte("ready"))
	})
	return serveMux(healthPort, mux, logger, "health")
}

// startMetricsServer listens on metricsPort for /metrics.
func startMetricsServer(metricsPort int, reg *prometheus.Registry, logger *slog.Logger) func() {
	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.HandlerFor(reg, promhttp.HandlerOpts{}))
	return serveMux(metricsPort, mux, logger, "metrics")
}

func serveMux(port int, mux *http.ServeMux, logger *slog.Logger, kind string) func() {
	srv := &http.Server{Addr: fmt.Sprintf(":%d", port), Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	ln, err := net.Listen("tcp", srv.Addr)
	if err != nil {
		logger.Error("listen failed", "server", kind, "addr", srv.Addr, "error", err.Error())
		return func() {}
	}
	go func() {
		if err := srv.Serve(ln); err != nil && err != http.ErrServerClosed {
			logger.Error("serve error", "server", kind, "error", err.Error())
		}
	}()
	return func() {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		_ = srv.Shutdown(ctx)
	}
}
