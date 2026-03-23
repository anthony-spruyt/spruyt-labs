package clients

import (
  "context"
  "fmt"

  "github.com/siderolabs/talos/pkg/machinery/client"
)

// RealTalosClient implements TalosClient using the Talos machinery client.
// Credentials are auto-discovered from /var/run/secrets/talos.dev (Talos SA CRD).
type RealTalosClient struct{}

// NewTalosClient creates a new Talos client that uses auto-discovered credentials.
func NewTalosClient() *RealTalosClient {
  return &RealTalosClient{}
}

// Shutdown initiates a shutdown on the specified Talos node.
func (t *RealTalosClient) Shutdown(ctx context.Context, nodeIP string, force bool) error {
  c, err := client.New(ctx,
    client.WithDefaultConfig(),
    client.WithEndpoints(nodeIP),
  )
  if err != nil {
    return fmt.Errorf("creating Talos client for node %s: %w", nodeIP, err)
  }
  defer c.Close() //nolint:errcheck

  // WithNodes sets the target node in the context metadata.
  nodeCtx := client.WithNodes(ctx, nodeIP)

  err = c.Shutdown(nodeCtx, client.WithShutdownForce(force))
  if err != nil {
    return fmt.Errorf("shutting down node %s: %w", nodeIP, err)
  }

  return nil
}

// Ping verifies connectivity to a Talos node by requesting its version.
func (t *RealTalosClient) Ping(ctx context.Context, nodeIP string) error {
  c, err := client.New(ctx,
    client.WithDefaultConfig(),
    client.WithEndpoints(nodeIP),
  )
  if err != nil {
    return fmt.Errorf("creating Talos client for node %s: %w", nodeIP, err)
  }
  defer c.Close() //nolint:errcheck

  nodeCtx := client.WithNodes(ctx, nodeIP)

  _, err = c.Version(nodeCtx)
  if err != nil {
    return fmt.Errorf("pinging Talos node %s: %w", nodeIP, err)
  }

  return nil
}

// Compile-time interface conformance check.
var _ TalosClient = (*RealTalosClient)(nil)
