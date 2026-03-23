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
  mu      sync.Mutex
  clients map[string]*client.Client
}

// NewTalosClient creates a new Talos client that uses auto-discovered credentials.
func NewTalosClient() *RealTalosClient {
  return &RealTalosClient{
    clients: make(map[string]*client.Client),
  }
}

// getOrCreateClient returns a cached client for the given node IP, creating one
// if it doesn't exist yet.
func (t *RealTalosClient) getOrCreateClient(ctx context.Context, nodeIP string) (*client.Client, error) {
  t.mu.Lock()
  defer t.mu.Unlock()

  if c, ok := t.clients[nodeIP]; ok {
    return c, nil
  }

  c, err := client.New(ctx,
    client.WithDefaultConfig(),
    client.WithEndpoints(nodeIP),
  )
  if err != nil {
    return nil, fmt.Errorf("creating Talos client for node %s: %w", nodeIP, err)
  }

  t.clients[nodeIP] = c
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
