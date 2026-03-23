package clients

import (
  "context"
  "fmt"
  "sync"

  "github.com/siderolabs/talos/pkg/machinery/client"
)

// RealTalosClient implements TalosClient using the Talos machinery client.
// Credentials are auto-discovered from /var/run/secrets/talos.dev (Talos SA CRD).
// Connections are cached per node IP and reused across calls.
type RealTalosClient struct {
  // mu protects the clients map for reads/writes but is NOT held during
  // gRPC dial. Per-node singleflight is handled via sync.Map of channels.
  mu       sync.Mutex
  clients  map[string]*client.Client
  inflight sync.Map // nodeIP -> chan struct{} — serializes per-node creation only
}

// NewTalosClient creates a new Talos client that uses auto-discovered credentials.
func NewTalosClient() *RealTalosClient {
  return &RealTalosClient{
    clients: make(map[string]*client.Client),
  }
}

// getOrCreateClient returns a cached client for the given node IP, creating one
// if it doesn't exist yet. Multiple goroutines calling this for different nodes
// will create clients concurrently; calls for the same node are serialized.
func (t *RealTalosClient) getOrCreateClient(ctx context.Context, nodeIP string) (*client.Client, error) {
  // Fast path: check cache under lock.
  t.mu.Lock()
  if c, ok := t.clients[nodeIP]; ok {
    t.mu.Unlock()
    return c, nil
  }
  t.mu.Unlock()

  // Per-node singleflight: only one goroutine dials per node at a time,
  // but different nodes can dial concurrently.
  ch := make(chan struct{})
  if existing, loaded := t.inflight.LoadOrStore(nodeIP, ch); loaded {
    // Another goroutine is already creating this client — wait for it.
    <-existing.(chan struct{})
    t.mu.Lock()
    c, ok := t.clients[nodeIP]
    t.mu.Unlock()
    if ok {
      return c, nil
    }
    return nil, fmt.Errorf("creating Talos client for node %s: concurrent creation failed", nodeIP)
  }
  // We own the creation — dial without holding the global lock.
  defer func() {
    close(ch)
    t.inflight.Delete(nodeIP)
  }()

  c, err := client.New(ctx,
    client.WithDefaultConfig(),
    client.WithEndpoints(nodeIP),
  )
  if err != nil {
    return nil, fmt.Errorf("creating Talos client for node %s: %w", nodeIP, err)
  }

  t.mu.Lock()
  t.clients[nodeIP] = c
  t.mu.Unlock()
  return c, nil
}

// Shutdown initiates a shutdown on the specified Talos node.
func (t *RealTalosClient) Shutdown(ctx context.Context, nodeIP string, force bool) error {
  c, err := t.getOrCreateClient(ctx, nodeIP)
  if err != nil {
    return err
  }

  nodeCtx := client.WithNodes(ctx, nodeIP)

  err = c.Shutdown(nodeCtx, client.WithShutdownForce(force))
  if err != nil {
    return fmt.Errorf("shutting down node %s: %w", nodeIP, err)
  }

  return nil
}

// Ping verifies connectivity to a Talos node by requesting its version.
func (t *RealTalosClient) Ping(ctx context.Context, nodeIP string) error {
  c, err := t.getOrCreateClient(ctx, nodeIP)
  if err != nil {
    return err
  }

  nodeCtx := client.WithNodes(ctx, nodeIP)

  _, err = c.Version(nodeCtx)
  if err != nil {
    return fmt.Errorf("pinging Talos node %s: %w", nodeIP, err)
  }

  return nil
}

// Close closes all cached Talos client connections.
func (t *RealTalosClient) Close() error {
  t.mu.Lock()
  defer t.mu.Unlock()

  for ip, c := range t.clients {
    c.Close() //nolint:errcheck
    delete(t.clients, ip)
  }

  return nil
}

// Compile-time interface conformance check.
var _ TalosClient = (*RealTalosClient)(nil)
