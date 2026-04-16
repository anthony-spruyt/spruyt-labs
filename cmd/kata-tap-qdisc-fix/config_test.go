package main

import (
	"os"
	"testing"
	"time"
)

func TestLoadConfigDefaults(t *testing.T) {
	for _, k := range []string{"DRY_RUN", "HEALTH_PORT", "METRICS_PORT", "NETNS_DIR", "LOG_LEVEL", "SWEEP_INTERVAL"} {
		os.Unsetenv(k)
	}
	cfg := LoadConfig()
	if cfg.DryRun != false {
		t.Errorf("DryRun = %v, want false", cfg.DryRun)
	}
	if cfg.HealthPort != 8080 {
		t.Errorf("HealthPort = %d, want 8080", cfg.HealthPort)
	}
	if cfg.MetricsPort != 9102 {
		t.Errorf("MetricsPort = %d, want 9102", cfg.MetricsPort)
	}
	if cfg.NetnsDir != "/run/netns" {
		t.Errorf("NetnsDir = %q, want /run/netns", cfg.NetnsDir)
	}
	if cfg.LogLevel != "info" {
		t.Errorf("LogLevel = %q, want info", cfg.LogLevel)
	}
	if cfg.SweepInterval != 30*time.Second {
		t.Errorf("SweepInterval = %v, want 30s", cfg.SweepInterval)
	}
}

func TestLoadConfigOverrides(t *testing.T) {
	t.Setenv("DRY_RUN", "true")
	t.Setenv("HEALTH_PORT", "9090")
	t.Setenv("METRICS_PORT", "9103")
	t.Setenv("NETNS_DIR", "/tmp/netns")
	t.Setenv("LOG_LEVEL", "debug")
	t.Setenv("SWEEP_INTERVAL", "60")

	cfg := LoadConfig()
	if !cfg.DryRun {
		t.Errorf("DryRun = false, want true")
	}
	if cfg.HealthPort != 9090 {
		t.Errorf("HealthPort = %d, want 9090", cfg.HealthPort)
	}
	if cfg.MetricsPort != 9103 {
		t.Errorf("MetricsPort = %d, want 9103", cfg.MetricsPort)
	}
	if cfg.NetnsDir != "/tmp/netns" {
		t.Errorf("NetnsDir = %q", cfg.NetnsDir)
	}
	if cfg.LogLevel != "debug" {
		t.Errorf("LogLevel = %q", cfg.LogLevel)
	}
	if cfg.SweepInterval != 60*time.Second {
		t.Errorf("SweepInterval = %v, want 60s", cfg.SweepInterval)
	}
}

func TestValidateRejectsBadPort(t *testing.T) {
	cfg := Config{HealthPort: 0, MetricsPort: 9102, NetnsDir: "/run/netns", LogLevel: "info", SweepInterval: time.Second}
	if err := cfg.Validate(); err == nil {
		t.Fatal("expected error for HealthPort 0")
	}
}

func TestValidateRejectsBadMetricsPort(t *testing.T) {
	cfg := Config{HealthPort: 8080, MetricsPort: 70000, NetnsDir: "/run/netns", LogLevel: "info", SweepInterval: time.Second}
	if err := cfg.Validate(); err == nil {
		t.Fatal("expected error for MetricsPort 70000")
	}
}

func TestValidateRejectsBadLogLevel(t *testing.T) {
	cfg := Config{HealthPort: 8080, MetricsPort: 9102, NetnsDir: "/run/netns", LogLevel: "verbose", SweepInterval: time.Second}
	if err := cfg.Validate(); err == nil {
		t.Fatal("expected error for LogLevel verbose")
	}
}

func TestValidateRejectsEmptyNetnsDir(t *testing.T) {
	cfg := Config{HealthPort: 8080, MetricsPort: 9102, NetnsDir: "", LogLevel: "info", SweepInterval: time.Second}
	if err := cfg.Validate(); err == nil {
		t.Fatal("expected error for empty NetnsDir")
	}
}

func TestValidateRejectsZeroSweepInterval(t *testing.T) {
	cfg := Config{HealthPort: 8080, MetricsPort: 9102, NetnsDir: "/run/netns", LogLevel: "info", SweepInterval: 0}
	if err := cfg.Validate(); err == nil {
		t.Fatal("expected error for SweepInterval 0")
	}
}
