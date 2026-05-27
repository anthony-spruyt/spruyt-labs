package clients

import (
	"context"
	"fmt"

	"github.com/siderolabs/talos/pkg/machinery/client"
)

// RealTalosClient implements TalosClient using the Talos machinery client.
// Credentials are auto-discovered from /var/run/secrets/talos.dev (Talos SA CRD).
// Each call creates an ephemeral connection to avoid stale TLS state after node reboots.
type RealTalosClient struct{}

// NewTalosClient creates a new Talos client.
func NewTalosClient() *RealTalosClient { return &RealTalosClient{} }

// Shutdown initiates a shutdown on the specified Talos node.
func (t *RealTalosClient) Shutdown(ctx context.Context, nodeIP string, force bool) error {
	c, err := client.New(ctx, client.WithDefaultConfig(), client.WithEndpoints(nodeIP))
	if err != nil {
		return fmt.Errorf("creating Talos client for node %s: %w", nodeIP, err)
	}
	defer c.Close()
	nodeCtx := client.WithNodes(ctx, nodeIP)
	if err := c.Shutdown(nodeCtx, client.WithShutdownForce(force)); err != nil {
		return fmt.Errorf("shutting down node %s: %w", nodeIP, err)
	}
	return nil
}

// Ping verifies connectivity to a Talos node by requesting its version.
func (t *RealTalosClient) Ping(ctx context.Context, nodeIP string) error {
	c, err := client.New(ctx, client.WithDefaultConfig(), client.WithEndpoints(nodeIP))
	if err != nil {
		return fmt.Errorf("creating Talos client for node %s: %w", nodeIP, err)
	}
	defer c.Close()
	nodeCtx := client.WithNodes(ctx, nodeIP)
	if _, err := c.Version(nodeCtx); err != nil {
		return fmt.Errorf("pinging Talos node %s: %w", nodeIP, err)
	}
	return nil
}

// Close is a no-op: ephemeral clients are closed after each use.
func (t *RealTalosClient) Close() error { return nil }

// Compile-time interface conformance check.
var _ TalosClient = (*RealTalosClient)(nil)
