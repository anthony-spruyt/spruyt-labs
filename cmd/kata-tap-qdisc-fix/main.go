package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/prometheus/client_golang/prometheus"
)

var (
	version = "dev"
	commit  = "unknown"
)

func main() { os.Exit(run()) }

func run() int {
	cfg := LoadConfig()
	if err := cfg.Validate(); err != nil {
		slog.New(slog.NewJSONHandler(os.Stderr, nil)).Error("invalid config", "error", err.Error())
		return 2
	}
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: parseLevel(cfg.LogLevel)}))
	logger.Info("kata-tap-qdisc-fix starting",
		"version", version,
		"commit", commit,
		"dry_run", cfg.DryRun,
		"netns_dir", cfg.NetnsDir,
		"sweep_interval", cfg.SweepInterval.String())

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	// Capture host netns from the main goroutine BEFORE any worker starts.
	if err := InitHostNetns(); err != nil {
		logger.Error("init host netns", "error", err.Error())
		return 3
	}

	reg := prometheus.NewRegistry()
	metrics := NewMetrics(reg)
	state := &readyState{}

	stopHealth := startHealthServer(cfg.HealthPort, state, logger)
	defer stopHealth()
	stopMetrics := startMetricsServer(cfg.MetricsPort, reg, logger)
	defer stopMetrics()

	opener := NewNetnsOpener()
	w := NewWatcher(cfg.NetnsDir, opener, NewQdiscManager, cfg.DryRun, cfg.SweepInterval, metrics, logger, realClock{})

	w.Start(ctx)
	state.markReady()

	<-ctx.Done()
	logger.Info("shutdown signal received")
	w.Stop()
	logger.Info("kata-tap-qdisc-fix stopped")
	return 0
}

func parseLevel(s string) slog.Level {
	switch s {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}
