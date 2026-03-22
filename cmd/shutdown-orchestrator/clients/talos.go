package clients

import (
  "context"
  "fmt"

  "github.com/siderolabs/talos/pkg/machinery/client"
)

// RealTalosClient implements TalosClient using the Talos machinery client.
type RealTalosClient struct {
  configPath string
}

// NewTalosClient creates a new Talos client that reads its config from the
// given file path.
func NewTalosClient(configPath string) *RealTalosClient {
  return &RealTalosClient{
    configPath: configPath,
  }
}

// Shutdown initiates a shutdown on the specified Talos node.
func (t *RealTalosClient) Shutdown(ctx context.Context, nodeIP string, force bool) error {
  c, err := client.New(ctx,
    client.WithConfigFromFile(t.configPath),
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

// Compile-time interface conformance check.
var _ TalosClient = (*RealTalosClient)(nil)
