package phases

import (
  "context"
  "log/slog"
  "sync"
  "time"

  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
)

// NodeEntry represents a node with its name and IP address.
type NodeEntry struct {
  Name string
  IP   string
}

// NodeConfig holds the configuration for the node shutdown phase.
type NodeConfig struct {
  Workers        []NodeEntry
  ControlPlane   []NodeEntry
  NodeName       string
  TestMode       bool
  PerNodeTimeout time.Duration
}

// NodePhase handles the ordered shutdown of cluster nodes.
type NodePhase struct {
  talos  clients.TalosClient
  logger *slog.Logger
}

// NewNodePhase creates a new NodePhase.
func NewNodePhase(talos clients.TalosClient, logger *slog.Logger) *NodePhase {
  return &NodePhase{
    talos:  talos,
    logger: logger,
  }
}

// ShutdownAll shuts down all nodes in the correct order:
// 1. Workers concurrently
// 2. Control plane sequentially
// In test mode, the node matching NodeName is skipped entirely.
// In real mode, the node matching NodeName is moved to the end of the CP list.
// If NodeName doesn't match any known node, a warning is logged and all nodes are shut down.
func (p *NodePhase) ShutdownAll(ctx context.Context, cfg NodeConfig) error {
  // Handle self-node logic for control plane.
  cpNodes := p.prepareControlPlane(cfg)

  // Phase 1: Workers concurrently.
  p.shutdownWorkersConcurrently(ctx, cfg.Workers, cfg.PerNodeTimeout)

  // Phase 2: Control plane sequentially.
  p.shutdownControlPlaneSequentially(ctx, cpNodes, cfg.PerNodeTimeout)

  return nil
}

// prepareControlPlane adjusts the control plane list based on NodeName and TestMode.
func (p *NodePhase) prepareControlPlane(cfg NodeConfig) []NodeEntry {
  cpNodes := make([]NodeEntry, len(cfg.ControlPlane))
  copy(cpNodes, cfg.ControlPlane)

  if cfg.NodeName == "" {
    return cpNodes
  }

  selfIndex := -1
  for i, n := range cpNodes {
    if n.Name == cfg.NodeName {
      selfIndex = i
      break
    }
  }

  // Also check workers — but NodeName should only affect CP ordering.
  if selfIndex == -1 {
    // Check if NodeName matches any worker.
    foundInWorkers := false
    for _, w := range cfg.Workers {
      if w.Name == cfg.NodeName {
        foundInWorkers = true
        break
      }
    }
    if !foundInWorkers {
      p.logger.Warn("NodeName not found in any node list, proceeding with all nodes",
        "nodeName", cfg.NodeName)
    }
    return cpNodes
  }

  if cfg.TestMode {
    // Skip self entirely. Build a new slice to avoid mutating the copy's
    // underlying array (a common Go foot-gun with append on sub-slices).
    p.logger.Info("test mode: skipping self node", "name", cfg.NodeName)
    result := make([]NodeEntry, 0, len(cpNodes)-1)
    result = append(result, cpNodes[:selfIndex]...)
    result = append(result, cpNodes[selfIndex+1:]...)
    return result
  }

  // Real mode: move self to last position using a fresh slice to avoid
  // mutating the underlying array.
  if selfIndex < len(cpNodes)-1 {
    self := cpNodes[selfIndex]
    result := make([]NodeEntry, 0, len(cpNodes))
    result = append(result, cpNodes[:selfIndex]...)
    result = append(result, cpNodes[selfIndex+1:]...)
    result = append(result, self)
    p.logger.Info("real mode: self node moved to last", "name", cfg.NodeName)
    return result
  }

  return cpNodes
}

// shutdownWorkersConcurrently shuts down all workers in parallel.
func (p *NodePhase) shutdownWorkersConcurrently(ctx context.Context, workers []NodeEntry, perNodeTimeout time.Duration) {
  if len(workers) == 0 {
    return
  }

  var wg sync.WaitGroup
  for _, w := range workers {
    wg.Add(1)
    go func(node NodeEntry) {
      defer wg.Done()
      p.shutdownNode(ctx, node, perNodeTimeout)
    }(w)
  }
  wg.Wait()
}

// shutdownControlPlaneSequentially shuts down control plane nodes one at a time.
func (p *NodePhase) shutdownControlPlaneSequentially(ctx context.Context, cpNodes []NodeEntry, perNodeTimeout time.Duration) {
  for _, node := range cpNodes {
    p.shutdownNode(ctx, node, perNodeTimeout)
  }
}

// shutdownNode shuts down a single node with a per-node timeout.
func (p *NodePhase) shutdownNode(ctx context.Context, node NodeEntry, perNodeTimeout time.Duration) {
  nodeCtx, cancel := context.WithTimeout(ctx, perNodeTimeout)
  defer cancel()

  p.logger.Info("shutting down node", "name", node.Name, "ip", node.IP)
  if err := p.talos.Shutdown(nodeCtx, node.IP, true); err != nil {
    p.logger.Error("failed to shut down node", "name", node.Name, "ip", node.IP, "error", err)
  }
}
