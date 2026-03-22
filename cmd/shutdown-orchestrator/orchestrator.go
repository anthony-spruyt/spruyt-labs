package main

import (
  "context"
  "errors"
  "fmt"
  "log/slog"
  "time"

  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/phases"
)

// Orchestrator coordinates the shutdown and recovery sequences.
type Orchestrator struct {
  cnpg   *phases.CNPGPhase
  ceph   *phases.CephPhase
  nodes  *phases.NodePhase
  kube   clients.KubeClient
  cfg    Config
  logger *slog.Logger
}

// NewOrchestrator creates a new Orchestrator.
func NewOrchestrator(
  cnpg *phases.CNPGPhase,
  ceph *phases.CephPhase,
  nodes *phases.NodePhase,
  kube clients.KubeClient,
  cfg Config,
  logger *slog.Logger,
) *Orchestrator {
  return &Orchestrator{
    cnpg:   cnpg,
    ceph:   ceph,
    nodes:  nodes,
    kube:   kube,
    cfg:    cfg,
    logger: logger,
  }
}

// Shutdown runs the full shutdown sequence:
// 1. CNPG hibernate
// 2. Ceph set noout
// 3. Ceph scale down
// 4. Node shutdown
func (o *Orchestrator) Shutdown(ctx context.Context) error {
  o.logger.Info("starting shutdown sequence")

  var errs []error

  if err := runPhase(ctx, o.logger, "cnpg-hibernate", o.cfg.CNPGPhaseTimeout, func(pctx context.Context) error {
    return o.cnpg.Hibernate(pctx)
  }); err != nil {
    errs = append(errs, fmt.Errorf("cnpg-hibernate: %w", err))
  }

  if err := runPhase(ctx, o.logger, "ceph-set-noout", o.cfg.CephFlagPhaseTimeout, func(pctx context.Context) error {
    return o.ceph.SetNoout(pctx)
  }); err != nil {
    errs = append(errs, fmt.Errorf("ceph-set-noout: %w", err))
  }

  if err := runPhase(ctx, o.logger, "ceph-scale-down", o.cfg.CephScalePhaseTimeout, func(pctx context.Context) error {
    return o.ceph.ScaleDown(pctx)
  }); err != nil {
    errs = append(errs, fmt.Errorf("ceph-scale-down: %w", err))
  }

  if err := runPhase(ctx, o.logger, "node-shutdown", o.cfg.NodeShutdownPhaseTimeout, func(pctx context.Context) error {
    nc, ncErr := o.nodeConfig(pctx)
    if ncErr != nil {
      return ncErr
    }
    return o.nodes.ShutdownAll(pctx, nc)
  }); err != nil {
    errs = append(errs, fmt.Errorf("node-shutdown: %w", err))
  }

  o.logger.Info("shutdown sequence complete")
  return errors.Join(errs...)
}

// Recover runs the full recovery sequence:
// 1. Wait for Ceph tools pod
// 2. Ceph scale up
// 3. Ceph unset noout
// 4. CNPG wake
func (o *Orchestrator) Recover(ctx context.Context) error {
  o.logger.Info("starting recovery sequence")

  var errs []error

  if err := runPhase(ctx, o.logger, "ceph-wait-tools", o.cfg.CephScalePhaseTimeout, func(pctx context.Context) error {
    return o.ceph.WaitForToolsPod(pctx)
  }); err != nil {
    errs = append(errs, fmt.Errorf("ceph-wait-tools: %w", err))
  }

  if err := runPhase(ctx, o.logger, "ceph-scale-up", o.cfg.CephScalePhaseTimeout, func(pctx context.Context) error {
    return o.ceph.ScaleUp(pctx)
  }); err != nil {
    errs = append(errs, fmt.Errorf("ceph-scale-up: %w", err))
  }

  if err := runPhase(ctx, o.logger, "ceph-unset-noout", o.cfg.CephFlagPhaseTimeout, func(pctx context.Context) error {
    return o.ceph.UnsetNoout(pctx)
  }); err != nil {
    errs = append(errs, fmt.Errorf("ceph-unset-noout: %w", err))
  }

  if err := runPhase(ctx, o.logger, "cnpg-wake", o.cfg.CNPGPhaseTimeout, func(pctx context.Context) error {
    return o.cnpg.Wake(pctx)
  }); err != nil {
    errs = append(errs, fmt.Errorf("cnpg-wake: %w", err))
  }

  // Verify cluster health — log warning only, do not fail recovery.
  if err := o.verifyHealth(ctx); err != nil {
    o.logger.Warn("post-recovery health check failed", "error", err)
  }

  o.logger.Info("recovery sequence complete")
  return errors.Join(errs...)
}

// NeedsRecovery checks if a previous shutdown needs recovery.
// Returns true if the Ceph noout flag is set or any CNPG cluster is hibernated.
func (o *Orchestrator) NeedsRecovery(ctx context.Context) (bool, error) {
  cephNeeds, err := o.ceph.NeedsRecovery(ctx)
  if err != nil {
    return false, fmt.Errorf("checking ceph recovery: %w", err)
  }
  if cephNeeds {
    o.logger.Info("ceph noout flag is set, recovery needed")
    return true, nil
  }

  clusters, err := o.kube.GetCNPGClusters(ctx)
  if err != nil {
    // If CNPG CRD is not installed, skip this check
    o.logger.Warn("failed to check CNPG clusters for recovery", "error", err)
    return false, nil
  }
  for _, c := range clusters {
    if c.Hibernated {
      o.logger.Info("found hibernated CNPG cluster, recovery needed",
        "namespace", c.Namespace, "name", c.Name)
      return true, nil
    }
  }

  return false, nil
}

// RunTest runs a full shutdown followed by recovery for test/validation.
func (o *Orchestrator) RunTest(ctx context.Context) error {
  o.logger.Info("starting test mode: shutdown then recovery")

  if err := o.Shutdown(ctx); err != nil {
    return fmt.Errorf("test shutdown failed: %w", err)
  }

  if err := o.Recover(ctx); err != nil {
    return fmt.Errorf("test recovery failed: %w", err)
  }

  o.logger.Info("test mode complete")
  return nil
}

// verifyHealth checks that all nodes are ready and logs the results.
func (o *Orchestrator) verifyHealth(ctx context.Context) error {
  nodes, err := o.kube.GetNodes(ctx)
  if err != nil {
    return fmt.Errorf("failed to get nodes: %w", err)
  }

  allReady := true
  for _, n := range nodes {
    if !n.Ready {
      o.logger.Warn("node not ready", "name", n.Name)
      allReady = false
    } else {
      o.logger.Info("node ready", "name", n.Name)
    }
  }

  if !allReady {
    return fmt.Errorf("not all nodes are ready")
  }

  o.logger.Info("all nodes are ready")
  return nil
}

// nodeConfig builds a NodeConfig from the orchestrator's Config.
// It resolves configured IPs to real Kubernetes node names via the API.
func (o *Orchestrator) nodeConfig(ctx context.Context) (phases.NodeConfig, error) {
  // Build IP-to-name map from the Kubernetes API.
  ipToName, err := o.resolveNodeNames(ctx)
  if err != nil {
    return phases.NodeConfig{}, fmt.Errorf("resolving node names: %w", err)
  }

  workers := make([]phases.NodeEntry, 0, len(o.cfg.WorkerIPs))
  for i, ip := range o.cfg.WorkerIPs {
    name := ipToName[ip]
    if name == "" {
      name = fmt.Sprintf("worker-%d", i+1)
      o.logger.Warn("could not resolve node name for worker IP, using fallback",
        "ip", ip, "fallbackName", name)
    }
    workers = append(workers, phases.NodeEntry{
      Name: name,
      IP:   ip,
    })
  }

  controlPlane := make([]phases.NodeEntry, 0, len(o.cfg.ControlPlaneIPs))
  for i, ip := range o.cfg.ControlPlaneIPs {
    name := ipToName[ip]
    if name == "" {
      name = fmt.Sprintf("cp-%d", i+1)
      o.logger.Warn("could not resolve node name for control plane IP, using fallback",
        "ip", ip, "fallbackName", name)
    }
    controlPlane = append(controlPlane, phases.NodeEntry{
      Name: name,
      IP:   ip,
    })
  }

  return phases.NodeConfig{
    Workers:        workers,
    ControlPlane:   controlPlane,
    NodeName:       o.cfg.NodeName,
    TestMode:       o.cfg.Mode == "test",
    PerNodeTimeout: 30 * time.Second,
  }, nil
}

// resolveNodeNames calls the Kubernetes API to build a map of IP -> node name.
func (o *Orchestrator) resolveNodeNames(ctx context.Context) (map[string]string, error) {
  nodes, err := o.kube.GetNodes(ctx)
  if err != nil {
    return nil, err
  }

  ipToName := make(map[string]string, len(nodes))
  for _, n := range nodes {
    if n.IP != "" {
      ipToName[n.IP] = n.Name
    }
  }

  return ipToName, nil
}

// runPhase executes a phase function with a timeout, logging start/end and errors.
// Errors are logged but not propagated — the sequence continues.
func runPhase(
  ctx context.Context,
  logger *slog.Logger,
  name string,
  timeout time.Duration,
  fn func(context.Context) error,
) error {
  logger.Info("phase starting", "phase", name, "timeout", timeout)

  phaseCtx, cancel := context.WithTimeout(ctx, timeout)
  defer cancel()

  start := time.Now()
  err := fn(phaseCtx)
  elapsed := time.Since(start)

  if err != nil {
    logger.Error("phase failed", "phase", name, "elapsed", elapsed, "error", err)
    return err
  }

  logger.Info("phase complete", "phase", name, "elapsed", elapsed)
  return nil
}
