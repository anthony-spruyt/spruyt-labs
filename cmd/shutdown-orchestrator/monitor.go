package main

import (
  "context"
  "fmt"
  "log/slog"
  "net/http"
  "strings"
  "sync/atomic"
  "time"

  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
)

// Monitor polls the UPS for status changes and triggers shutdown when power
// has been lost for longer than the configured ShutdownDelay.
type Monitor struct {
  ups          clients.UPSClient
  shutdownFn   func(context.Context) error
  cfg          Config
  logger       *slog.Logger
  shuttingDown atomic.Bool
}

// NewMonitor creates a new Monitor. If logger is nil, a default logger is used.
func NewMonitor(ups clients.UPSClient, shutdownFn func(context.Context) error, cfg Config, logger *slog.Logger) *Monitor {
  if logger == nil {
    logger = slog.Default()
  }
  return &Monitor{
    ups:        ups,
    shutdownFn: shutdownFn,
    cfg:        cfg,
    logger:     logger,
  }
}

// Run starts both the health server and the poll loop. It blocks until ctx is
// cancelled or the shutdown sequence completes.
func (m *Monitor) Run(ctx context.Context) error {
  // Start health server.
  mux := http.NewServeMux()
  mux.HandleFunc("/healthz", m.healthHandler)
  srv := &http.Server{
    Addr:    fmt.Sprintf(":%d", m.cfg.HealthPort),
    Handler: mux,
  }

  go func() {
    m.logger.Info("starting health server", "port", m.cfg.HealthPort)
    if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
      m.logger.Error("health server error", "error", err)
    }
  }()

  defer func() {
    shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    _ = srv.Shutdown(shutdownCtx)
  }()

  return m.RunPollLoop(ctx)
}

// RunPollLoop polls the UPS at PollInterval and triggers shutdown after
// ShutdownDelay seconds on battery. Exposed separately for testability.
func (m *Monitor) RunPollLoop(ctx context.Context) error {
  pollInterval := time.Duration(m.cfg.PollInterval) * time.Second
  shutdownDelay := time.Duration(m.cfg.ShutdownDelay) * time.Second

  ticker := time.NewTicker(pollInterval)
  defer ticker.Stop()

  var onBatteryElapsed time.Duration

  for {
    select {
    case <-ctx.Done():
      return ctx.Err()
    case <-ticker.C:
      status, err := m.ups.GetStatus(ctx)
      if err != nil {
        m.logger.Error("failed to poll UPS", "error", err)
        // Don't reset or advance onBatteryElapsed on poll errors.
        // Resetting would be dangerous: if NUT crashes during a real
        // outage, the countdown would reset and shutdown never triggers.
        // Not advancing is conservative — the countdown holds its
        // position until a successful poll confirms the UPS state.
        continue
      }

      if strings.Contains(status, "OB") {
        onBatteryElapsed += pollInterval
        m.logger.Warn("UPS on battery",
          "status", status,
          "elapsed", onBatteryElapsed,
          "delay", shutdownDelay,
        )

        if onBatteryElapsed >= shutdownDelay {
          m.logger.Warn("shutdown delay exceeded, triggering shutdown")
          m.shuttingDown.Store(true)

          // Enforce UPS runtime budget as an overall deadline for the
          // shutdown sequence. Remaining budget = total budget minus
          // time already spent on battery.
          budgetRemaining := time.Duration(m.cfg.UPSRuntimeBudget)*time.Second - onBatteryElapsed
          if budgetRemaining <= 0 {
            budgetRemaining = 30 * time.Second // absolute minimum
          }
          shutdownCtx, shutdownCancel := context.WithTimeout(ctx, budgetRemaining)
          m.logger.Info("shutdown budget", "remaining", budgetRemaining)

          err := m.shutdownFn(shutdownCtx)
          shutdownCancel()
          if err != nil {
            m.logger.Error("shutdown failed", "error", err)
            return fmt.Errorf("shutdown failed: %w", err)
          }
          return nil
        }
      } else {
        if onBatteryElapsed > 0 {
          m.logger.Info("power restored, resetting countdown",
            "status", status,
            "elapsed", onBatteryElapsed,
          )
        }
        onBatteryElapsed = 0
      }
    }
  }
}

// healthHandler responds to health check requests.
func (m *Monitor) healthHandler(w http.ResponseWriter, r *http.Request) {
  if m.shuttingDown.Load() {
    w.WriteHeader(http.StatusServiceUnavailable)
    fmt.Fprintln(w, "shutting down")
    return
  }
  w.WriteHeader(http.StatusOK)
  fmt.Fprintln(w, "ok")
}
