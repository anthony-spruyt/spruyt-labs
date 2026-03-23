package main

import (
  "context"
  "fmt"
  "log/slog"
  "net"
  "net/http"
  "os"
  "os/signal"
  "syscall"
  "time"

  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/phases"
)

// version and commit are set at build time via -ldflags.
var (
  version = "dev"
  commit  = "unknown"
)

func main() {
  logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

  cfg := LoadConfig(logger)
  if err := cfg.Validate(); err != nil {
    logger.Error("invalid configuration", "error", err)
    os.Exit(1)
  }

  logger.Info("starting shutdown-orchestrator", "mode", cfg.Mode, "version", version, "commit", commit)

  ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
  defer cancel()

  switch cfg.Mode {
  case "monitor":
    if err := runMonitor(ctx, cfg, logger); err != nil {
      logger.Error("monitor failed", "error", err)
      os.Exit(1)
    }
  case "test":
    if os.Getenv("CONFIRM_TEST") != "yes" {
      logger.Error("test mode executes a REAL shutdown against the live cluster; set CONFIRM_TEST=yes to proceed")
      os.Exit(1)
    }
    if err := runTest(ctx, cfg, logger); err != nil {
      logger.Error("test failed", "error", err)
      os.Exit(1)
    }
  case "preflight":
    if err := runPreflight(ctx, cfg, logger); err != nil {
      logger.Error("preflight failed", "error", err)
      os.Exit(1)
    }
  }
}

func buildClients(cfg Config, logger *slog.Logger) (clients.KubeClient, clients.TalosClient, clients.UPSClient, error) {
  kube, err := clients.NewKubeClient()
  if err != nil {
    return nil, nil, nil, fmt.Errorf("creating kube client: %w", err)
  }

  talos := clients.NewTalosClient()
  ups := clients.NewNUTClient(cfg.NUTServer, cfg.NUTPort, cfg.UPSName)

  return kube, talos, ups, nil
}

func buildOrchestrator(kube clients.KubeClient, talos clients.TalosClient, cfg Config, logger *slog.Logger) *Orchestrator {
  cnpg := phases.NewCNPGPhase(kube, logger)
  ceph := phases.NewCephPhase(kube, logger)
  nodes := phases.NewNodePhase(talos, logger)
  return NewOrchestrator(cnpg, ceph, nodes, kube, cfg, logger)
}

func runMonitor(ctx context.Context, cfg Config, logger *slog.Logger) error {
  kube, talos, ups, err := buildClients(cfg, logger)
  if err != nil {
    return err
  }
  defer talos.Close()
  defer ups.Close()

  // Run preflight checks before starting the monitor loop.
  // If any check fails, refuse to start monitoring.
  checker := NewPreflightChecker(kube, talos, ups, cfg, logger)
  results := checker.RunAll(ctx)
  failed := 0
  for _, r := range results {
    if !r.Passed {
      logger.Error("preflight check failed", "check", r.Check, "error", r.Error)
      failed++
    }
  }
  if failed > 0 {
    return fmt.Errorf("preflight failed: %d/%d checks failed, refusing to start monitor", failed, len(results))
  }
  logger.Info("all preflight checks passed")

  orch := buildOrchestrator(kube, talos, cfg, logger)

  // Check for recovery on startup
  needsRecovery, err := orch.NeedsRecovery(ctx)
  if err != nil {
    logger.Warn("failed to check recovery state", "error", err)
  }
  if needsRecovery {
    logger.Info("recovery needed, running recovery sequence")
    if err := orch.Recover(ctx); err != nil {
      logger.Error("recovery failed", "error", err)
    }
  }

  monitor := NewMonitor(ups, orch.Shutdown, cfg, logger)
  return monitor.Run(ctx)
}

func runTest(ctx context.Context, cfg Config, logger *slog.Logger) error {
  kube, talos, ups, err := buildClients(cfg, logger)
  if err != nil {
    return err
  }
  defer talos.Close()
  defer ups.Close()

  orch := buildOrchestrator(kube, talos, cfg, logger)
  return orch.RunTest(ctx)
}

func runPreflight(ctx context.Context, cfg Config, logger *slog.Logger) error {
  kube, talos, ups, err := buildClients(cfg, logger)
  if err != nil {
    return fmt.Errorf("creating clients: %w", err)
  }
  defer talos.Close()
  defer ups.Close()

  checker := NewPreflightChecker(kube, talos, ups, cfg, logger)
  results := checker.RunAll(ctx)

  failed := 0
  for _, r := range results {
    if r.Passed {
      logger.Info("preflight check passed", "check", r.Check)
    } else {
      logger.Error("preflight check failed", "check", r.Check, "error", r.Error)
      failed++
    }
  }

  logger.Info("preflight complete", "passed", len(results)-failed, "failed", failed, "total", len(results))
  if failed > 0 {
    logger.Error("preflight failed, serving health endpoint until restarted")
  }

  // Keep the pod alive with the health endpoint so probes pass and
  // operators can inspect the logs without a CrashLoopBackOff cycle.
  logger.Info("preflight idle, waiting for signal", "port", cfg.HealthPort)
  mon := &Monitor{cfg: cfg, logger: logger}
  mux := http.NewServeMux()
  mux.HandleFunc("/healthz", mon.healthHandler)
  srv := &http.Server{Handler: mux}

  ln, listenErr := net.Listen("tcp", fmt.Sprintf(":%d", cfg.HealthPort))
  if listenErr != nil {
    return fmt.Errorf("binding health server port %d: %w", cfg.HealthPort, listenErr)
  }
  go func() {
    if srvErr := srv.Serve(ln); srvErr != nil && srvErr != http.ErrServerClosed {
      logger.Error("health server error", "error", srvErr)
    }
  }()

  <-ctx.Done()
  shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
  defer cancel()
  _ = srv.Shutdown(shutdownCtx)
  return nil
}
