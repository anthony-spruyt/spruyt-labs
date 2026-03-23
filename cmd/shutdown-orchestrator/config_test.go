package main

import (
  "testing"
)

func TestLoadConfigDefaults(t *testing.T) {
  // Clear any env vars that might interfere
  for _, key := range []string{"MODE", "NUT_SERVER", "NUT_PORT", "UPS_NAME",
    "SHUTDOWN_DELAY", "POLL_INTERVAL", "UPS_RUNTIME_BUDGET", "HEALTH_PORT"} {
    t.Setenv(key, "")
  }

  cfg := LoadConfig(nil)

  if cfg.Mode != "monitor" {
    t.Errorf("Mode = %q, want %q", cfg.Mode, "monitor")
  }
  if cfg.NUTServer != "nut-server-nut.nut-system.svc.cluster.local" {
    t.Errorf("NUTServer = %q, want default", cfg.NUTServer)
  }
  if cfg.NUTPort != 3493 {
    t.Errorf("NUTPort = %d, want 3493", cfg.NUTPort)
  }
  if cfg.UPSName != "cp1500" {
    t.Errorf("UPSName = %q, want %q", cfg.UPSName, "cp1500")
  }
  if cfg.ShutdownDelay != 30 {
    t.Errorf("ShutdownDelay = %d, want 30", cfg.ShutdownDelay)
  }
  if cfg.PollInterval != 5 {
    t.Errorf("PollInterval = %d, want 5", cfg.PollInterval)
  }
  if cfg.UPSRuntimeBudget != 600 {
    t.Errorf("UPSRuntimeBudget = %d, want 600", cfg.UPSRuntimeBudget)
  }
  if cfg.HealthPort != 8080 {
    t.Errorf("HealthPort = %d, want 8080", cfg.HealthPort)
  }
}

func TestLoadConfigFromEnv(t *testing.T) {
  t.Setenv("MODE", "test")
  t.Setenv("SHUTDOWN_DELAY", "60")
  t.Setenv("UPS_RUNTIME_BUDGET", "900")

  cfg := LoadConfig(nil)

  if cfg.Mode != "test" {
    t.Errorf("Mode = %q, want %q", cfg.Mode, "test")
  }
  if cfg.ShutdownDelay != 60 {
    t.Errorf("ShutdownDelay = %d, want 60", cfg.ShutdownDelay)
  }
  if cfg.UPSRuntimeBudget != 900 {
    t.Errorf("UPSRuntimeBudget = %d, want 900", cfg.UPSRuntimeBudget)
  }
}

func TestLoadConfigNodeIPs(t *testing.T) {
  t.Setenv("MS_01_1_IP4", "10.0.0.1")
  t.Setenv("MS_01_2_IP4", "10.0.0.2")
  t.Setenv("MS_01_3_IP4", "10.0.0.3")
  t.Setenv("E2_1_IP4", "10.0.1.1")
  t.Setenv("E2_2_IP4", "10.0.1.2")
  t.Setenv("E2_3_IP4", "10.0.1.3")

  cfg := LoadConfig(nil)

  if len(cfg.WorkerIPs) != 3 {
    t.Fatalf("WorkerIPs len = %d, want 3", len(cfg.WorkerIPs))
  }
  if len(cfg.ControlPlaneIPs) != 3 {
    t.Fatalf("ControlPlaneIPs len = %d, want 3", len(cfg.ControlPlaneIPs))
  }
  if cfg.WorkerIPs[0] != "10.0.0.1" {
    t.Errorf("WorkerIPs[0] = %q, want %q", cfg.WorkerIPs[0], "10.0.0.1")
  }
}

func TestLoadConfigInvalidMode(t *testing.T) {
  t.Setenv("MODE", "invalid")

  cfg := LoadConfig(nil)
  if err := cfg.Validate(); err == nil {
    t.Error("Validate() = nil, want error for invalid mode")
  }
}
