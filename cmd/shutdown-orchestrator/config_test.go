package main

import (
  "os"
  "testing"
)

func TestLoadConfigDefaults(t *testing.T) {
  // Clear any env vars that might interfere
  for _, key := range []string{"MODE", "NUT_SERVER", "NUT_PORT", "UPS_NAME",
    "SHUTDOWN_DELAY", "POLL_INTERVAL", "UPS_RUNTIME_BUDGET", "HEALTH_PORT"} {
    os.Unsetenv(key)
  }

  cfg := LoadConfig()

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
  os.Setenv("MODE", "test")
  os.Setenv("SHUTDOWN_DELAY", "60")
  os.Setenv("UPS_RUNTIME_BUDGET", "900")
  defer func() {
    os.Unsetenv("MODE")
    os.Unsetenv("SHUTDOWN_DELAY")
    os.Unsetenv("UPS_RUNTIME_BUDGET")
  }()

  cfg := LoadConfig()

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
  os.Setenv("MS_01_1_IP4", "10.0.0.1")
  os.Setenv("MS_01_2_IP4", "10.0.0.2")
  os.Setenv("MS_01_3_IP4", "10.0.0.3")
  os.Setenv("E2_1_IP4", "10.0.1.1")
  os.Setenv("E2_2_IP4", "10.0.1.2")
  os.Setenv("E2_3_IP4", "10.0.1.3")
  defer func() {
    for _, k := range []string{"MS_01_1_IP4", "MS_01_2_IP4", "MS_01_3_IP4",
      "E2_1_IP4", "E2_2_IP4", "E2_3_IP4"} {
      os.Unsetenv(k)
    }
  }()

  cfg := LoadConfig()

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
  os.Setenv("MODE", "invalid")
  defer os.Unsetenv("MODE")

  cfg := LoadConfig()
  if err := cfg.Validate(); err == nil {
    t.Error("Validate() = nil, want error for invalid mode")
  }
}
