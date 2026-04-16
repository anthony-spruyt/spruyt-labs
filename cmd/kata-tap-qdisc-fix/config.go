package main

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

type Config struct {
	DryRun        bool
	HealthPort    int
	MetricsPort   int
	NetnsDir      string
	LogLevel      string
	SweepInterval time.Duration
}

func LoadConfig() Config {
	return Config{
		DryRun:        envBool("DRY_RUN", false),
		HealthPort:    envInt("HEALTH_PORT", 8080),
		MetricsPort:   envInt("METRICS_PORT", 9102),
		NetnsDir:      envString("NETNS_DIR", "/run/netns"),
		LogLevel:      envString("LOG_LEVEL", "info"),
		SweepInterval: time.Duration(envInt("SWEEP_INTERVAL", 30)) * time.Second,
	}
}

func (c Config) Validate() error {
	if c.HealthPort < 1 || c.HealthPort > 65535 {
		return fmt.Errorf("HEALTH_PORT must be 1..65535, got %d", c.HealthPort)
	}
	if c.MetricsPort < 1 || c.MetricsPort > 65535 {
		return fmt.Errorf("METRICS_PORT must be 1..65535, got %d", c.MetricsPort)
	}
	if c.NetnsDir == "" {
		return fmt.Errorf("NETNS_DIR must not be empty")
	}
	switch c.LogLevel {
	case "debug", "info", "warn", "error":
	default:
		return fmt.Errorf("LOG_LEVEL must be one of debug, info, warn, error (got %q)", c.LogLevel)
	}
	if c.SweepInterval <= 0 {
		return fmt.Errorf("SWEEP_INTERVAL must be > 0, got %v", c.SweepInterval)
	}
	return nil
}

func envString(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return n
}

func envBool(key string, def bool) bool {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		return def
	}
	return b
}
