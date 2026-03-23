package main

import (
  "fmt"
  "log/slog"
  "os"
  "strconv"
  "time"
)

type Config struct {
  Mode             string
  NUTServer        string
  NUTPort          int
  UPSName          string
  ShutdownDelay    time.Duration
  PollInterval     time.Duration
  UPSRuntimeBudget time.Duration
  HealthPort       int
  NodeName         string

  // Phase timeouts
  CNPGPhaseTimeout         time.Duration
  CephFlagPhaseTimeout     time.Duration
  CephScalePhaseTimeout    time.Duration
  CephHealthWaitTimeout    time.Duration
  NodeShutdownPhaseTimeout time.Duration
  PerNodeTimeout           time.Duration
  CephWaitToolsTimeout     time.Duration

  // Node IPs
  WorkerIPs       []string
  ControlPlaneIPs []string
}

func LoadConfig(logger *slog.Logger) Config {
  if logger == nil {
    logger = slog.Default()
  }
  cfg := Config{
    Mode:                     envOrDefault("MODE", "monitor"),
    NUTServer:                envOrDefault("NUT_SERVER", "nut-server-nut.nut-system.svc.cluster.local"),
    NUTPort:                  envIntOrDefault(logger, "NUT_PORT", 3493),
    UPSName:                  envOrDefault("UPS_NAME", "cp1500"),
    ShutdownDelay:            time.Duration(envIntOrDefault(logger, "SHUTDOWN_DELAY", 30)) * time.Second,
    PollInterval:             time.Duration(envIntOrDefault(logger, "POLL_INTERVAL", 5)) * time.Second,
    UPSRuntimeBudget:         time.Duration(envIntOrDefault(logger, "UPS_RUNTIME_BUDGET", 600)) * time.Second,
    HealthPort:               envIntOrDefault(logger, "HEALTH_PORT", 8080),
    NodeName:                 os.Getenv("NODE_NAME"),
    CNPGPhaseTimeout:         time.Duration(envIntOrDefault(logger, "CNPG_PHASE_TIMEOUT", 60)) * time.Second,
    CephFlagPhaseTimeout:     time.Duration(envIntOrDefault(logger, "CEPH_FLAG_PHASE_TIMEOUT", 15)) * time.Second,
    CephScalePhaseTimeout:    time.Duration(envIntOrDefault(logger, "CEPH_SCALE_PHASE_TIMEOUT", 60)) * time.Second,
    CephHealthWaitTimeout:    time.Duration(envIntOrDefault(logger, "CEPH_HEALTH_WAIT_TIMEOUT", 300)) * time.Second,
    NodeShutdownPhaseTimeout: time.Duration(envIntOrDefault(logger, "NODE_SHUTDOWN_PHASE_TIMEOUT", 120)) * time.Second,
    PerNodeTimeout:           time.Duration(envIntOrDefault(logger, "PER_NODE_TIMEOUT", 15)) * time.Second,
    CephWaitToolsTimeout:     time.Duration(envIntOrDefault(logger, "CEPH_WAIT_TOOLS_TIMEOUT", 600)) * time.Second,
  }

  // Collect non-empty node IPs
  for _, key := range []string{"MS_01_1_IP4", "MS_01_2_IP4", "MS_01_3_IP4"} {
    if ip := os.Getenv(key); ip != "" {
      cfg.WorkerIPs = append(cfg.WorkerIPs, ip)
    }
  }
  for _, key := range []string{"E2_1_IP4", "E2_2_IP4", "E2_3_IP4"} {
    if ip := os.Getenv(key); ip != "" {
      cfg.ControlPlaneIPs = append(cfg.ControlPlaneIPs, ip)
    }
  }

  return cfg
}

func (c Config) Validate() error {
  switch c.Mode {
  case "monitor", "test", "preflight":
    // valid
  default:
    return fmt.Errorf("invalid mode %q: must be monitor, test, or preflight", c.Mode)
  }

  if c.PollInterval <= 0 {
    return fmt.Errorf("POLL_INTERVAL must be positive, got %s", c.PollInterval)
  }
  if c.ShutdownDelay <= 0 {
    return fmt.Errorf("SHUTDOWN_DELAY must be positive, got %s", c.ShutdownDelay)
  }
  if c.UPSRuntimeBudget <= 0 {
    return fmt.Errorf("UPS_RUNTIME_BUDGET must be positive, got %s", c.UPSRuntimeBudget)
  }

  // Phase timeouts must be positive to avoid immediately-cancelled contexts.
  for _, check := range []struct {
    name  string
    value time.Duration
  }{
    {"CNPG_PHASE_TIMEOUT", c.CNPGPhaseTimeout},
    {"CEPH_FLAG_PHASE_TIMEOUT", c.CephFlagPhaseTimeout},
    {"CEPH_SCALE_PHASE_TIMEOUT", c.CephScalePhaseTimeout},
    {"CEPH_HEALTH_WAIT_TIMEOUT", c.CephHealthWaitTimeout},
    {"NODE_SHUTDOWN_PHASE_TIMEOUT", c.NodeShutdownPhaseTimeout},
    {"PER_NODE_TIMEOUT", c.PerNodeTimeout},
    {"CEPH_WAIT_TOOLS_TIMEOUT", c.CephWaitToolsTimeout},
  } {
    if check.value <= 0 {
      return fmt.Errorf("%s must be positive, got %s", check.name, check.value)
    }
  }

  // Node IPs and NODE_NAME are required for monitor and test modes to perform
  // shutdown/recovery. Preflight mode checks IPs as part of its own validation.
  if c.Mode == "monitor" || c.Mode == "test" {
    if c.NodeName == "" {
      return fmt.Errorf("NODE_NAME must be set in %s mode", c.Mode)
    }
    if len(c.ControlPlaneIPs) == 0 {
      return fmt.Errorf("no control plane node IPs configured (E2_*_IP4 env vars)")
    }
    if len(c.WorkerIPs) == 0 {
      return fmt.Errorf("no worker node IPs configured (MS_*_IP4 env vars)")
    }
  }

  // Warn if shutdown phase timeouts exceed the UPS runtime budget minus shutdown delay.
  // CephHealthWaitTimeout and CephWaitToolsTimeout are excluded because they only
  // apply during recovery (power restored), not during the battery-constrained shutdown.
  totalPhaseTime := c.CNPGPhaseTimeout + c.CephFlagPhaseTimeout + c.CephScalePhaseTimeout + c.NodeShutdownPhaseTimeout
  availableBudget := c.UPSRuntimeBudget - c.ShutdownDelay
  if totalPhaseTime > availableBudget {
    return fmt.Errorf("phase timeouts (%s) exceed available UPS budget (%s = %s runtime - %s delay)",
      totalPhaseTime, availableBudget, c.UPSRuntimeBudget, c.ShutdownDelay)
  }

  return nil
}

func envOrDefault(key, def string) string {
  if v := os.Getenv(key); v != "" {
    return v
  }
  return def
}

func envIntOrDefault(logger *slog.Logger, key string, def int) int {
  if v := os.Getenv(key); v != "" {
    n, err := strconv.Atoi(v)
    if err != nil {
      logger.Warn("invalid integer env var, using default", "key", key, "value", v, "default", def)
      return def
    }
    return n
  }
  return def
}
