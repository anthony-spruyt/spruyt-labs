package phases

import (
  "context"
  "errors"
  "fmt"
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
  // Handle self-node logic for both workers and control plane.
  workers, cpNodes := p.prepareNodeLists(cfg)

  // Phase 1: Workers concurrently.
  workerErrs := p.shutdownWorkersConcurrently(ctx, workers, cfg.PerNodeTimeout)

  // Phase 2: Control plane sequentially.
  cpErrs := p.shutdownControlPlaneSequentially(ctx, cpNodes, cfg.PerNodeTimeout)

  allErrs := append(workerErrs, cpErrs...)
  return errors.Join(allErrs...)
}

// prepareNodeLists adjusts both the worker and control plane lists based on
// NodeName and TestMode. If the self node is a worker, it is handled the same
// way as a CP self node (skipped in test mode, moved to last in real mode).
func (p *NodePhase) prepareNodeLists(cfg NodeConfig) ([]NodeEntry, []NodeEntry) {
  workers := make([]NodeEntry, len(cfg.Workers))
  copy(workers, cfg.Workers)
  cpNodes := make([]NodeEntry, len(cfg.ControlPlane))
  copy(cpNodes, cfg.ControlPlane)

  if cfg.NodeName == "" {
    return workers, cpNodes
  }

  // Check control plane first.
  for i, n := range cpNodes {
    if n.Name == cfg.NodeName {
      if cfg.TestMode {
        p.logger.Info("test mode: skipping self node", "name", cfg.NodeName)
        result := make([]NodeEntry, 0, len(cpNodes)-1)
        result = append(result, cpNodes[:i]...)
        result = append(result, cpNodes[i+1:]...)
        return workers, result
      }
      // Real mode: move self to last CP position.
      if i < len(cpNodes)-1 {
        self := cpNodes[i]
        result := make([]NodeEntry, 0, len(cpNodes))
        result = append(result, cpNodes[:i]...)
        result = append(result, cpNodes[i+1:]...)
        result = append(result, self)
        p.logger.Info("real mode: self node moved to last", "name", cfg.NodeName)
        return workers, result
      }
      return workers, cpNodes
    }
  }

  // Check workers.
  for i, w := range workers {
    if w.Name == cfg.NodeName {
      if cfg.TestMode {
        p.logger.Info("test mode: skipping self worker node", "name", cfg.NodeName)
        result := make([]NodeEntry, 0, len(workers)-1)
        result = append(result, workers[:i]...)
        result = append(result, workers[i+1:]...)
        return result, cpNodes
      }
      // Real mode: remove from workers — it will be shut down after all
      // CP nodes by appending it as the very last operation.
      p.logger.Info("real mode: self worker node will shut down last", "name", cfg.NodeName)
      self := workers[i]
      filteredWorkers := make([]NodeEntry, 0, len(workers)-1)
      filteredWorkers = append(filteredWorkers, workers[:i]...)
      filteredWorkers = append(filteredWorkers, workers[i+1:]...)
      // Append self after all CP nodes so it shuts down last.
      cpNodes = append(cpNodes, self)
      return filteredWorkers, cpNodes
    }
  }

  p.logger.Warn("NodeName not found in any node list, proceeding with all nodes",
    "nodeName", cfg.NodeName)
  return workers, cpNodes
}

// shutdownWorkersConcurrently shuts down all workers in parallel.
// Returns a slice of errors from failed shutdown attempts.
func (p *NodePhase) shutdownWorkersConcurrently(ctx context.Context, workers []NodeEntry, perNodeTimeout time.Duration) []error {
  if len(workers) == 0 {
    return nil
  }

  var (
    wg   sync.WaitGroup
    mu   sync.Mutex
    errs []error
  )
  for _, w := range workers {
    wg.Add(1)
    go func(node NodeEntry) {
      defer wg.Done()
      if err := p.shutdownNode(ctx, node, perNodeTimeout); err != nil {
        mu.Lock()
        errs = append(errs, err)
        mu.Unlock()
      }
    }(w)
  }
  wg.Wait()
  return errs
}

// shutdownControlPlaneSequentially shuts down control plane nodes one at a time.
// Returns a slice of errors from failed shutdown attempts.
func (p *NodePhase) shutdownControlPlaneSequentially(ctx context.Context, cpNodes []NodeEntry, perNodeTimeout time.Duration) []error {
  var errs []error
  for _, node := range cpNodes {
    if err := p.shutdownNode(ctx, node, perNodeTimeout); err != nil {
      errs = append(errs, err)
    }
  }
  return errs
}

// shutdownNode shuts down a single node with a per-node timeout.
func (p *NodePhase) shutdownNode(ctx context.Context, node NodeEntry, perNodeTimeout time.Duration) error {
  nodeCtx, cancel := context.WithTimeout(ctx, perNodeTimeout)
  defer cancel()

  p.logger.Info("shutting down node", "name", node.Name, "ip", node.IP)
  if err := p.talos.Shutdown(nodeCtx, node.IP, true); err != nil {
    p.logger.Error("failed to shut down node", "name", node.Name, "ip", node.IP, "error", err)
    return fmt.Errorf("node %s (%s): %w", node.Name, node.IP, err)
  }
  return nil
}
