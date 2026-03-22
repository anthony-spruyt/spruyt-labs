package main

import (
  "fmt"
  "os"
  "strconv"
  "time"
)

type Config struct {
  Mode             string
  NUTServer        string
  NUTPort          int
  UPSName          string
  ShutdownDelay    int
  PollInterval     int
  UPSRuntimeBudget int
  HealthPort       int
  NodeName         string

  // Phase timeouts
  CNPGPhaseTimeout         time.Duration
  CephFlagPhaseTimeout     time.Duration
  CephScalePhaseTimeout    time.Duration
  NodeShutdownPhaseTimeout time.Duration

  // Node IPs
  WorkerIPs       []string
  ControlPlaneIPs []string
}

func LoadConfig() Config {
  cfg := Config{
    Mode:                     envOrDefault("MODE", "monitor"),
    NUTServer:                envOrDefault("NUT_SERVER", "nut-server-nut.nut-system.svc.cluster.local"),
    NUTPort:                  envIntOrDefault("NUT_PORT", 3493),
    UPSName:                  envOrDefault("UPS_NAME", "cp1500"),
    ShutdownDelay:            envIntOrDefault("SHUTDOWN_DELAY", 30),
    PollInterval:             envIntOrDefault("POLL_INTERVAL", 5),
    UPSRuntimeBudget:         envIntOrDefault("UPS_RUNTIME_BUDGET", 600),
    HealthPort:               envIntOrDefault("HEALTH_PORT", 8080),
    NodeName:                 os.Getenv("NODE_NAME"),
    CNPGPhaseTimeout:         time.Duration(envIntOrDefault("CNPG_PHASE_TIMEOUT", 60)) * time.Second,
    CephFlagPhaseTimeout:     time.Duration(envIntOrDefault("CEPH_FLAG_PHASE_TIMEOUT", 15)) * time.Second,
    CephScalePhaseTimeout:    time.Duration(envIntOrDefault("CEPH_SCALE_PHASE_TIMEOUT", 60)) * time.Second,
    NodeShutdownPhaseTimeout: time.Duration(envIntOrDefault("NODE_SHUTDOWN_PHASE_TIMEOUT", 120)) * time.Second,
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
  return nil
}

func envOrDefault(key, def string) string {
  if v := os.Getenv(key); v != "" {
    return v
  }
  return def
}

func envIntOrDefault(key string, def int) int {
  if v := os.Getenv(key); v != "" {
    if n, err := strconv.Atoi(v); err == nil {
      return n
    }
  }
  return def
}
