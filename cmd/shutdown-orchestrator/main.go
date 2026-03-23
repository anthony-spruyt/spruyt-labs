package main

import (
  "context"
  "fmt"
  "log/slog"
  "os"
  "os/signal"
  "syscall"

  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/phases"
)

func main() {
  logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

  cfg := LoadConfig(logger)
  if err := cfg.Validate(); err != nil {
    logger.Error("invalid configuration", "error", err)
    os.Exit(1)
  }

  logger.Info("starting shutdown-orchestrator", "mode", cfg.Mode)

  ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
  defer cancel()

  switch cfg.Mode {
  case "monitor":
    if err := runMonitor(ctx, cfg, logger); err != nil {
      logger.Error("monitor failed", "error", err)
      os.Exit(1)
    }
  case "test":
    if err := runTest(ctx, cfg, logger); err != nil {
      logger.Error("test failed", "error", err)
      os.Exit(1)
    }
  case "preflight":
    runPreflight(ctx, cfg, logger)
  }
}

func buildClients(cfg Config, logger *slog.Logger) (clients.KubeClient, *clients.RealTalosClient, clients.UPSClient, error) {
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
  kube, talos, _, err := buildClients(cfg, logger)
  if err != nil {
    return err
  }
  defer talos.Close()

  orch := buildOrchestrator(kube, talos, cfg, logger)
  return orch.RunTest(ctx)
}

func runPreflight(ctx context.Context, cfg Config, logger *slog.Logger) {
  kube, talos, ups, err := buildClients(cfg, logger)
  if err != nil {
    logger.Error("failed to create clients", "error", err)
    fmt.Println("FAIL: could not create clients")
    os.Exit(1)
  }
  defer talos.Close()

  checker := NewPreflightChecker(kube, talos, ups, cfg, logger)
  results := checker.RunAll(ctx)

  failed := 0
  for _, r := range results {
    if r.Passed {
      fmt.Printf("PASS: %s\n", r.Check)
    } else {
      fmt.Printf("FAIL: %s - %s\n", r.Check, r.Error)
      failed++
    }
  }

  fmt.Printf("\n%d/%d checks passed\n", len(results)-failed, len(results))
  if failed > 0 {
    os.Exit(1)
  }
}
