package phases

import (
  "context"
  "fmt"
  "io"
  "log/slog"
  "sync"
  "testing"
  "time"
)

// shutdownCall records a single Shutdown invocation.
type shutdownCall struct {
  NodeIP string
  Force  bool
}

// mockTalosClient records Shutdown calls and can return per-node errors or block.
type mockTalosClient struct {
  mu         sync.Mutex
  calls      []shutdownCall
  errors     map[string]error         // nodeIP -> error
  delays     map[string]time.Duration // nodeIP -> artificial delay
  blockNodes map[string]bool          // nodeIP -> block forever (until ctx done)
}

func newMockTalosClient() *mockTalosClient {
  return &mockTalosClient{
    errors:     make(map[string]error),
    delays:     make(map[string]time.Duration),
    blockNodes: make(map[string]bool),
  }
}

func (m *mockTalosClient) Shutdown(ctx context.Context, nodeIP string, force bool) error {
  if m.blockNodes[nodeIP] {
    <-ctx.Done()
    return ctx.Err()
  }
  if d, ok := m.delays[nodeIP]; ok {
    select {
    case <-time.After(d):
    case <-ctx.Done():
      return ctx.Err()
    }
  }

  m.mu.Lock()
  defer m.mu.Unlock()
  m.calls = append(m.calls, shutdownCall{NodeIP: nodeIP, Force: force})
  if err, ok := m.errors[nodeIP]; ok {
    return err
  }
  return nil
}

func (m *mockTalosClient) getCalls() []shutdownCall {
  m.mu.Lock()
  defer m.mu.Unlock()
  out := make([]shutdownCall, len(m.calls))
  copy(out, m.calls)
  return out
}

func newNodeTestLogger() *slog.Logger {
  return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func TestNodeShutdownAll(t *testing.T) {
  mock := newMockTalosClient()
  // Add small delay to workers so we can detect ordering:
  // workers have a 10ms delay, CP nodes have a 50ms delay built into sequential execution.
  phase := NewNodePhase(mock, newNodeTestLogger())

  cfg := NodeConfig{
    Workers: []NodeEntry{
      {Name: "worker-1", IP: "10.0.0.1"},
      {Name: "worker-2", IP: "10.0.0.2"},
    },
    ControlPlane: []NodeEntry{
      {Name: "cp-1", IP: "10.1.0.1"},
      {Name: "cp-2", IP: "10.1.0.2"},
    },
    PerNodeTimeout: 5 * time.Second,
  }

  err := phase.ShutdownAll(context.Background(), cfg)
  if err != nil {
    t.Fatalf("ShutdownAll() returned error: %v", err)
  }

  calls := mock.getCalls()
  if len(calls) != 4 {
    t.Fatalf("expected 4 shutdown calls, got %d", len(calls))
  }

  // Workers must appear before any control plane node.
  workerIPs := map[string]bool{"10.0.0.1": true, "10.0.0.2": true}
  cpIPs := map[string]bool{"10.1.0.1": true, "10.1.0.2": true}

  firstCPIndex := -1
  lastWorkerIndex := -1
  for i, c := range calls {
    if workerIPs[c.NodeIP] && i > lastWorkerIndex {
      lastWorkerIndex = i
    }
    if cpIPs[c.NodeIP] && (firstCPIndex == -1 || i < firstCPIndex) {
      firstCPIndex = i
    }
  }

  if lastWorkerIndex >= firstCPIndex {
    t.Errorf("workers must be shut down before control plane: lastWorker=%d, firstCP=%d", lastWorkerIndex, firstCPIndex)
  }
}

func TestNodeWorkersConcurrent(t *testing.T) {
  mock := newMockTalosClient()
  // Each worker has a 50ms delay; if sequential this would take 150ms+.
  mock.delays["10.0.0.1"] = 50 * time.Millisecond
  mock.delays["10.0.0.2"] = 50 * time.Millisecond
  mock.delays["10.0.0.3"] = 50 * time.Millisecond

  phase := NewNodePhase(mock, newNodeTestLogger())

  cfg := NodeConfig{
    Workers: []NodeEntry{
      {Name: "w1", IP: "10.0.0.1"},
      {Name: "w2", IP: "10.0.0.2"},
      {Name: "w3", IP: "10.0.0.3"},
    },
    PerNodeTimeout: 5 * time.Second,
  }

  start := time.Now()
  err := phase.ShutdownAll(context.Background(), cfg)
  elapsed := time.Since(start)

  if err != nil {
    t.Fatalf("ShutdownAll() returned error: %v", err)
  }

  calls := mock.getCalls()
  if len(calls) != 3 {
    t.Fatalf("expected 3 shutdown calls, got %d", len(calls))
  }

  // Concurrent execution should finish in ~50ms, not 150ms.
  if elapsed > 120*time.Millisecond {
    t.Errorf("workers took %v, expected concurrent execution (<120ms)", elapsed)
  }
}

func TestNodeControlPlaneSequential(t *testing.T) {
  mock := newMockTalosClient()
  phase := NewNodePhase(mock, newNodeTestLogger())

  cfg := NodeConfig{
    ControlPlane: []NodeEntry{
      {Name: "cp-1", IP: "10.1.0.1"},
      {Name: "cp-2", IP: "10.1.0.2"},
      {Name: "cp-3", IP: "10.1.0.3"},
    },
    PerNodeTimeout: 5 * time.Second,
  }

  err := phase.ShutdownAll(context.Background(), cfg)
  if err != nil {
    t.Fatalf("ShutdownAll() returned error: %v", err)
  }

  calls := mock.getCalls()
  if len(calls) != 3 {
    t.Fatalf("expected 3 calls, got %d", len(calls))
  }

  // Verify order matches input order.
  for i, expected := range []string{"10.1.0.1", "10.1.0.2", "10.1.0.3"} {
    if calls[i].NodeIP != expected {
      t.Errorf("call[%d] = %s, want %s", i, calls[i].NodeIP, expected)
    }
  }
}

func TestNodeSelfSkipTestMode(t *testing.T) {
  mock := newMockTalosClient()
  phase := NewNodePhase(mock, newNodeTestLogger())

  cfg := NodeConfig{
    Workers: []NodeEntry{
      {Name: "worker-1", IP: "10.0.0.1"},
    },
    ControlPlane: []NodeEntry{
      {Name: "cp-1", IP: "10.1.0.1"},
      {Name: "cp-2", IP: "10.1.0.2"},
    },
    NodeName:       "cp-1",
    TestMode:       true,
    PerNodeTimeout: 5 * time.Second,
  }

  err := phase.ShutdownAll(context.Background(), cfg)
  if err != nil {
    t.Fatalf("ShutdownAll() returned error: %v", err)
  }

  calls := mock.getCalls()
  // Should have worker-1 and cp-2 only; cp-1 (self) skipped.
  if len(calls) != 2 {
    t.Fatalf("expected 2 calls (self skipped), got %d: %+v", len(calls), calls)
  }
  for _, c := range calls {
    if c.NodeIP == "10.1.0.1" {
      t.Errorf("self node cp-1 (10.1.0.1) should have been skipped in test mode")
    }
  }
}

func TestNodeSelfLastRealMode(t *testing.T) {
  mock := newMockTalosClient()
  phase := NewNodePhase(mock, newNodeTestLogger())

  cfg := NodeConfig{
    ControlPlane: []NodeEntry{
      {Name: "cp-1", IP: "10.1.0.1"},
      {Name: "cp-2", IP: "10.1.0.2"},
      {Name: "cp-3", IP: "10.1.0.3"},
    },
    NodeName:       "cp-1",
    TestMode:       false,
    PerNodeTimeout: 5 * time.Second,
  }

  err := phase.ShutdownAll(context.Background(), cfg)
  if err != nil {
    t.Fatalf("ShutdownAll() returned error: %v", err)
  }

  calls := mock.getCalls()
  if len(calls) != 3 {
    t.Fatalf("expected 3 calls, got %d", len(calls))
  }

  // Self (cp-1) must be the last call.
  lastCall := calls[len(calls)-1]
  if lastCall.NodeIP != "10.1.0.1" {
    t.Errorf("expected self node cp-1 (10.1.0.1) to be last, got %s", lastCall.NodeIP)
  }
}

func TestNodeNameNotFound(t *testing.T) {
  mock := newMockTalosClient()
  phase := NewNodePhase(mock, newNodeTestLogger())

  cfg := NodeConfig{
    Workers: []NodeEntry{
      {Name: "worker-1", IP: "10.0.0.1"},
    },
    ControlPlane: []NodeEntry{
      {Name: "cp-1", IP: "10.1.0.1"},
    },
    NodeName:       "unknown-node",
    PerNodeTimeout: 5 * time.Second,
  }

  err := phase.ShutdownAll(context.Background(), cfg)
  if err != nil {
    t.Fatalf("ShutdownAll() returned error: %v", err)
  }

  calls := mock.getCalls()
  if len(calls) != 2 {
    t.Fatalf("expected 2 calls (all nodes), got %d", len(calls))
  }
}

func TestNodeSingleTimeout(t *testing.T) {
  mock := newMockTalosClient()
  mock.blockNodes["10.0.0.2"] = true // This worker blocks forever.

  phase := NewNodePhase(mock, newNodeTestLogger())

  cfg := NodeConfig{
    Workers: []NodeEntry{
      {Name: "w1", IP: "10.0.0.1"},
      {Name: "w2", IP: "10.0.0.2"}, // blocks
      {Name: "w3", IP: "10.0.0.3"},
    },
    ControlPlane: []NodeEntry{
      {Name: "cp-1", IP: "10.1.0.1"},
    },
    PerNodeTimeout: 100 * time.Millisecond,
  }

  err := phase.ShutdownAll(context.Background(), cfg)
  if err != nil {
    t.Fatalf("ShutdownAll() returned error: %v", err)
  }

  calls := mock.getCalls()
  // w1, w3, and cp-1 should succeed; w2 timed out but others still called.
  calledIPs := make(map[string]bool)
  for _, c := range calls {
    calledIPs[c.NodeIP] = true
  }

  for _, ip := range []string{"10.0.0.1", "10.0.0.3", "10.1.0.1"} {
    if !calledIPs[ip] {
      t.Errorf("expected node %s to be called despite timeout on another node", ip)
    }
  }
}

func TestNodeAllForce(t *testing.T) {
  mock := newMockTalosClient()
  phase := NewNodePhase(mock, newNodeTestLogger())

  cfg := NodeConfig{
    Workers: []NodeEntry{
      {Name: "w1", IP: "10.0.0.1"},
      {Name: "w2", IP: "10.0.0.2"},
    },
    ControlPlane: []NodeEntry{
      {Name: "cp-1", IP: "10.1.0.1"},
    },
    PerNodeTimeout: 5 * time.Second,
  }

  err := phase.ShutdownAll(context.Background(), cfg)
  if err != nil {
    t.Fatalf("ShutdownAll() returned error: %v", err)
  }

  calls := mock.getCalls()
  if len(calls) != 3 {
    t.Fatalf("expected 3 calls, got %d", len(calls))
  }

  for i, c := range calls {
    if !c.Force {
      t.Errorf("call[%d] to %s had force=false, want true", i, c.NodeIP)
    }
  }
}

func TestNodeShutdownErrorContinues(t *testing.T) {
  mock := newMockTalosClient()
  mock.errors["10.0.0.1"] = fmt.Errorf("connection refused")

  phase := NewNodePhase(mock, newNodeTestLogger())

  cfg := NodeConfig{
    Workers: []NodeEntry{
      {Name: "w1", IP: "10.0.0.1"},
      {Name: "w2", IP: "10.0.0.2"},
    },
    ControlPlane: []NodeEntry{
      {Name: "cp-1", IP: "10.1.0.1"},
    },
    PerNodeTimeout: 5 * time.Second,
  }

  err := phase.ShutdownAll(context.Background(), cfg)
  if err != nil {
    t.Fatalf("ShutdownAll() returned error: %v", err)
  }

  calls := mock.getCalls()
  // All 3 should be attempted even though w1 errors.
  if len(calls) != 3 {
    t.Fatalf("expected 3 calls, got %d", len(calls))
  }
}
