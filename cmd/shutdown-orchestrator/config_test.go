package main

import (
  "testing"
  "time"
)

// validConfig returns a Config with all fields set to valid values.
func validConfig() Config {
  return Config{
    Mode:                     "monitor",
    NodeName:                 "test-node",
    PollInterval:             5 * time.Second,
    ShutdownDelay:            30 * time.Second,
    UPSRuntimeBudget:         600 * time.Second,
    CNPGPhaseTimeout:         60 * time.Second,
    CephFlagPhaseTimeout:     15 * time.Second,
    CephScalePhaseTimeout:    60 * time.Second,
    CephHealthWaitTimeout:    300 * time.Second,
    NodeShutdownPhaseTimeout: 120 * time.Second,
    PerNodeTimeout:           15 * time.Second,
    CephWaitToolsTimeout:     600 * time.Second,
    WorkerIPs:                []string{"10.0.0.1"},
    ControlPlaneIPs:          []string{"10.0.1.1"},
  }
}

func TestLoadConfigDefaults(t *testing.T) {
  // Ensure env vars are empty so defaults are used (t.Setenv restores originals on cleanup).
  // Setting to "" is sufficient since envOrDefault treats empty as unset.
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
  if cfg.ShutdownDelay != 30*time.Second {
    t.Errorf("ShutdownDelay = %s, want 30s", cfg.ShutdownDelay)
  }
  if cfg.PollInterval != 5*time.Second {
    t.Errorf("PollInterval = %s, want 5s", cfg.PollInterval)
  }
  if cfg.UPSRuntimeBudget != 600*time.Second {
    t.Errorf("UPSRuntimeBudget = %s, want 10m0s", cfg.UPSRuntimeBudget)
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
  if cfg.ShutdownDelay != 60*time.Second {
    t.Errorf("ShutdownDelay = %s, want 1m0s", cfg.ShutdownDelay)
  }
  if cfg.UPSRuntimeBudget != 900*time.Second {
    t.Errorf("UPSRuntimeBudget = %s, want 15m0s", cfg.UPSRuntimeBudget)
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

func TestValidateValidConfig(t *testing.T) {
  cfg := validConfig()
  if err := cfg.Validate(); err != nil {
    t.Errorf("Validate() = %v, want nil for valid config", err)
  }
}

func TestValidateEmptyNodeName(t *testing.T) {
  cfg := validConfig()
  cfg.NodeName = ""
  if err := cfg.Validate(); err == nil {
    t.Error("Validate() = nil, want error for empty NodeName in monitor mode")
  }
}

func TestLoadConfigInvalidMode(t *testing.T) {
  t.Setenv("MODE", "invalid")

  cfg := LoadConfig(nil)
  if err := cfg.Validate(); err == nil {
    t.Error("Validate() = nil, want error for invalid mode")
  }
}

func TestValidateZeroPollInterval(t *testing.T) {
  cfg := validConfig()
  cfg.PollInterval = 0
  if err := cfg.Validate(); err == nil {
    t.Error("Validate() = nil, want error for zero PollInterval")
  }
}

func TestValidateZeroShutdownDelay(t *testing.T) {
  cfg := validConfig()
  cfg.ShutdownDelay = 0
  if err := cfg.Validate(); err == nil {
    t.Error("Validate() = nil, want error for zero ShutdownDelay")
  }
}

func TestValidateZeroUPSRuntimeBudget(t *testing.T) {
  cfg := validConfig()
  cfg.UPSRuntimeBudget = 0
  if err := cfg.Validate(); err == nil {
    t.Error("Validate() = nil, want error for zero UPSRuntimeBudget")
  }
}

func TestValidateNoControlPlaneIPs(t *testing.T) {
  cfg := validConfig()
  cfg.ControlPlaneIPs = nil
  if err := cfg.Validate(); err == nil {
    t.Error("Validate() = nil, want error for missing control plane IPs")
  }
}

func TestValidateNoWorkerIPs(t *testing.T) {
  cfg := validConfig()
  cfg.WorkerIPs = nil
  if err := cfg.Validate(); err == nil {
    t.Error("Validate() = nil, want error for missing worker IPs")
  }
}

func TestValidateNoIPsInTestMode(t *testing.T) {
  cfg := validConfig()
  cfg.Mode = "test"
  cfg.WorkerIPs = nil
  cfg.ControlPlaneIPs = nil
  if err := cfg.Validate(); err == nil {
    t.Error("Validate() = nil, want error for missing IPs in test mode")
  }
}

func TestValidateZeroPerNodeTimeout(t *testing.T) {
  cfg := validConfig()
  cfg.PerNodeTimeout = 0
  if err := cfg.Validate(); err == nil {
    t.Error("Validate() = nil, want error for zero PerNodeTimeout")
  }
}

func TestValidateBudgetOverflow(t *testing.T) {
  cfg := validConfig()
  // Set phase timeouts that exceed the available budget (runtime - delay).
  cfg.UPSRuntimeBudget = 60 * time.Second
  cfg.ShutdownDelay = 30 * time.Second
  // Total phase timeouts: 60+15+60+120 = 255s, available: 60-30 = 30s
  if err := cfg.Validate(); err == nil {
    t.Error("Validate() = nil, want error for phase timeouts exceeding UPS budget")
  }
}

func TestValidatePreflightSkipsIPCheck(t *testing.T) {
  cfg := validConfig()
  cfg.Mode = "preflight"
  cfg.WorkerIPs = nil
  cfg.ControlPlaneIPs = nil
  if err := cfg.Validate(); err != nil {
    t.Errorf("Validate() = %v, want nil for preflight without IPs", err)
  }
}
