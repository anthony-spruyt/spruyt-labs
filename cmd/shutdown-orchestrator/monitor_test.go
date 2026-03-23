package main

import (
  "context"
  "fmt"
  "io"
  "net"
  "net/http"
  "sync"
  "sync/atomic"
  "testing"
  "time"
)

// mockUPSClient implements clients.UPSClient for testing.
type mockUPSClient struct {
  mu       sync.Mutex
  statuses []string
  index    int
  err      error
}

func (m *mockUPSClient) Close() error { return nil }

func (m *mockUPSClient) GetStatus(_ context.Context) (string, error) {
  m.mu.Lock()
  defer m.mu.Unlock()

  if m.err != nil {
    return "", m.err
  }
  if m.index >= len(m.statuses) {
    // Return last status indefinitely
    return m.statuses[len(m.statuses)-1], nil
  }
  s := m.statuses[m.index]
  m.index++
  return s, nil
}

// shutdownTracker records whether shutdownFn was called.
type shutdownTracker struct {
  called atomic.Bool
  err    error
}

func (s *shutdownTracker) shutdownFn(_ context.Context) error {
  s.called.Store(true)
  return s.err
}

func testConfig(poll, delay time.Duration, healthPort int) Config {
  return Config{
    Mode:             "monitor",
    PollInterval:     poll,
    ShutdownDelay:    delay,
    HealthPort:       healthPort,
    UPSRuntimeBudget: 10 * time.Minute,
  }
}

func TestMonitorUPSOnline(t *testing.T) {
  ups := &mockUPSClient{
    statuses: []string{"OL", "OL", "OL", "OL", "OL"},
  }
  tracker := &shutdownTracker{}
  cfg := testConfig(50*time.Millisecond, 500*time.Millisecond, 0)
  mon := NewMonitor(ups, tracker.shutdownFn, cfg, discardLogger())

  ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
  defer cancel()

  err := mon.RunPollLoop(ctx)
  if err != nil && err != context.DeadlineExceeded {
    t.Fatalf("unexpected error: %v", err)
  }

  if tracker.called.Load() {
    t.Error("shutdown should not have been triggered while UPS is online")
  }
}

func TestMonitorPowerLossDetection(t *testing.T) {
  ups := &mockUPSClient{
    statuses: []string{"OB", "OB", "OB"},
  }
  tracker := &shutdownTracker{}
  cfg := testConfig(50*time.Millisecond, 500*time.Millisecond, 0)
  mon := NewMonitor(ups, tracker.shutdownFn, cfg, discardLogger())

  ctx, cancel := context.WithTimeout(context.Background(), 150*time.Millisecond)
  defer cancel()

  _ = mon.RunPollLoop(ctx)

  if tracker.called.Load() {
    t.Error("shutdown should not trigger before delay expires")
  }

  // shuttingDown should only be true once the delay expires and shutdown begins,
  // not during the countdown period.
  if mon.shuttingDown.Load() {
    t.Error("expected shuttingDown to be false during countdown (before delay expires)")
  }
}

func TestMonitorPowerRestoredDuringCountdown(t *testing.T) {
  // OB for 2 polls, then OL — countdown should reset.
  ups := &mockUPSClient{
    statuses: []string{"OB", "OB", "OL", "OL", "OL"},
  }
  tracker := &shutdownTracker{}
  cfg := testConfig(50*time.Millisecond, 500*time.Millisecond, 0)
  mon := NewMonitor(ups, tracker.shutdownFn, cfg, discardLogger())

  ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
  defer cancel()

  _ = mon.RunPollLoop(ctx)

  if tracker.called.Load() {
    t.Error("shutdown should not have been triggered after power restored")
  }

  if mon.shuttingDown.Load() {
    t.Error("shuttingDown should be false after power restored")
  }
}

func TestMonitorCountdownExpires(t *testing.T) {
  // Enough OB polls to exceed the shutdown delay.
  ups := &mockUPSClient{
    statuses: []string{"OB", "OB", "OB", "OB", "OB", "OB", "OB", "OB", "OB", "OB"},
  }
  tracker := &shutdownTracker{}
  // Poll every 50ms, shutdown delay 100ms — should trigger after 2 OB polls.
  cfg := testConfig(50*time.Millisecond, 100*time.Millisecond, 0)
  mon := NewMonitor(ups, tracker.shutdownFn, cfg, discardLogger())

  ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
  defer cancel()

  _ = mon.RunPollLoop(ctx)

  if !tracker.called.Load() {
    t.Error("shutdown should have been triggered after countdown expired")
  }
}

func TestMonitorHealthEndpoint(t *testing.T) {
  ups := &mockUPSClient{
    statuses: []string{"OL"},
  }
  tracker := &shutdownTracker{}
  // Use a random available port.
  cfg := testConfig(60*time.Second, 300*time.Second, 0)
  mon := NewMonitor(ups, tracker.shutdownFn, cfg, discardLogger())

  // Start health server on a free port.
  mux := http.NewServeMux()
  mux.HandleFunc("/healthz", mon.healthHandler)
  srv := &http.Server{
    Addr:    ":0",
    Handler: mux,
  }

  // Use a listener to get the actual port.
  ln, err := (&net.ListenConfig{}).Listen(context.Background(), "tcp", "127.0.0.1:0")
  if err != nil {
    t.Fatalf("failed to listen: %v", err)
  }
  defer ln.Close()

  go srv.Serve(ln)
  defer srv.Close()

  addr := ln.Addr().String()
  url := fmt.Sprintf("http://%s/healthz", addr)

  resp, err := http.Get(url)
  if err != nil {
    t.Fatalf("health request failed: %v", err)
  }
  defer resp.Body.Close()

  if resp.StatusCode != http.StatusOK {
    t.Errorf("expected status 200, got %d", resp.StatusCode)
  }

  body, _ := io.ReadAll(resp.Body)
  if string(body) != "ok\n" {
    t.Errorf("expected body %q, got %q", "ok\n", string(body))
  }
}

func TestIsOnBattery(t *testing.T) {
  tests := []struct {
    status string
    want   bool
  }{
    {"OL", false},
    {"OB", true},
    {"OB DISCHRG", true},
    {"OL CHRG", false},
    {"", false},
    {"OB LB", true},
  }

  for _, tt := range tests {
    t.Run(fmt.Sprintf("status=%q", tt.status), func(t *testing.T) {
      if got := isOnBattery(tt.status); got != tt.want {
        t.Errorf("isOnBattery(%q) = %v, want %v", tt.status, got, tt.want)
      }
    })
  }
}
