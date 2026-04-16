package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

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
		"sweep_interval", cfg.SweepInterval.String())

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	// Capture host netns from the main goroutine BEFORE any worker starts.
	if err := InitHostNetns(); err != nil {
		logger.Error("init host netns", "error", err.Error())
		return 3
	}

	hostInode, err := HostNetnsInode("/proc", 1)
	if err != nil {
		logger.Error("read host netns inode", "error", err.Error())
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
	scanner := NewProcScanner(opener, NewQdiscManager, cfg.DryRun, logger, hostInode, "/proc")

	state.markReady()

	ticker := time.NewTicker(cfg.SweepInterval)
	defer ticker.Stop()

	runSweep := func() {
		res, err := scanner.Sweep(ctx)
		if err != nil {
			metrics.ReplaceFailuresTotal.Inc()
			logger.Error("sweep failed", "error", err.Error())
			return
		}
		metrics.SweepsTotal.Inc()
		if res.Replaced > 0 {
			metrics.ReplacementsTotal.Add(float64(res.Replaced))
		}
		logger.Debug("sweep ok",
			"elapsed", res.Elapsed,
			"total_inodes", res.TotalInodes,
			"unique_netns", res.UniqueNetns,
			"replaced", res.Replaced,
			"taps_found", res.TapsFound)
	}

	runSweep() // initial sweep

	for {
		select {
		case <-ctx.Done():
			logger.Info("shutdown signal received")
			logger.Info("kata-tap-qdisc-fix stopped")
			return 0
		case <-ticker.C:
			runSweep()
		}
	}
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
