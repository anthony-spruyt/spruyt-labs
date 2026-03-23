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

func testConfig(pollMs, delayMs, healthPort int) Config {
  return Config{
    Mode:          "monitor",
    PollInterval:  pollMs,
    ShutdownDelay: delayMs,
    HealthPort:    healthPort,
  }
}

func TestMonitorUPSOnline(t *testing.T) {
  ups := &mockUPSClient{
    statuses: []string{"OL", "OL", "OL", "OL", "OL"},
  }
  tracker := &shutdownTracker{}
  // PollInterval=50ms, ShutdownDelay=200ms (in seconds for config, but we use
  // small values and treat them as milliseconds in test config).
  // Actually Config uses seconds. We'll use 1s poll and 3s delay to keep tests
  // fast but correct. Instead, let's use very small second values.
  // The monitor uses time.Duration(cfg.PollInterval) * time.Second, so we need
  // to work in seconds. For fast tests we'll override with millisecond-scale.
  // Better: use millisecond values and adjust the monitor to accept Duration.
  // Since Config stores int seconds, let's keep PollInterval=1, ShutdownDelay=3
  // and use a context timeout to limit the test. 5 polls at 1s = 5s is too slow.
  //
  // We'll use PollInterval=1 (1 second) but cancel after 3 polls worth.
  // Actually for unit tests we want them fast. Let's just set poll=1, delay=5
  // and cancel the context after a few polls. The monitor should exit cleanly.

  cfg := testConfig(1, 5, 0) // poll=1s, delay=5s
  mon := NewMonitor(ups, tracker.shutdownFn, cfg, nil)

  ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
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
  // Poll every 1s, shutdown delay 10s — cancel before shutdown triggers.
  cfg := testConfig(1, 10, 0)
  mon := NewMonitor(ups, tracker.shutdownFn, cfg, nil)

  ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
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
  cfg := testConfig(1, 10, 0) // delay 10s, won't expire in 2s
  mon := NewMonitor(ups, tracker.shutdownFn, cfg, nil)

  ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
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
  // Poll every 1s, shutdown delay 2s — should trigger after 2 OB polls.
  cfg := testConfig(1, 2, 0)
  mon := NewMonitor(ups, tracker.shutdownFn, cfg, nil)

  ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
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
  cfg := testConfig(60, 300, 0)
  mon := NewMonitor(ups, tracker.shutdownFn, cfg, nil)

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
