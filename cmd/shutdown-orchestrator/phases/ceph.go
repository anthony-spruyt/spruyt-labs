package phases

import (
  "context"
  "errors"
  "log/slog"
  "strings"
  "time"

  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
)

const (
  cephNamespace      = "rook-ceph"
  cephToolsDeploy    = "rook-ceph-tools"
  cephOperatorDeploy = "rook-ceph-operator"
)

// CephPhase handles Ceph cluster shutdown and recovery operations.
type CephPhase struct {
  kube   clients.KubeClient
  logger *slog.Logger
}

// NewCephPhase creates a new CephPhase.
func NewCephPhase(kube clients.KubeClient, logger *slog.Logger) *CephPhase {
  return &CephPhase{
    kube:   kube,
    logger: logger,
  }
}

// SetNoout sets the noout flag on the Ceph cluster via the tools pod.
// If the tools deployment does not exist, it logs a warning and returns nil.
func (p *CephPhase) SetNoout(ctx context.Context) error {
  exists, err := p.kube.DeploymentExists(ctx, cephNamespace, cephToolsDeploy)
  if err != nil {
    return err
  }
  if !exists {
    p.logger.Warn("ceph tools deployment not found, skipping noout set")
    return nil
  }

  _, err = p.kube.ExecInDeployment(ctx, cephNamespace, cephToolsDeploy, []string{"ceph", "osd", "set", "noout"})
  if err != nil {
    return err
  }

  p.logger.Info("ceph noout flag set")
  return nil
}

// UnsetNoout removes the noout flag from the Ceph cluster via the tools pod.
func (p *CephPhase) UnsetNoout(ctx context.Context) error {
  exists, err := p.kube.DeploymentExists(ctx, cephNamespace, cephToolsDeploy)
  if err != nil {
    return err
  }
  if !exists {
    p.logger.Warn("ceph tools deployment not found, skipping noout unset")
    return nil
  }

  _, err = p.kube.ExecInDeployment(ctx, cephNamespace, cephToolsDeploy, []string{"ceph", "osd", "unset", "noout"})
  if err != nil {
    return err
  }

  p.logger.Info("ceph noout flag unset")
  return nil
}

// ScaleDown scales Ceph components to 0 replicas in order:
// operator -> OSDs -> monitors -> managers.
// If scaling one component fails, it logs a warning and continues.
// Returns a combined error of all failures for inclusion in the phase summary.
func (p *CephPhase) ScaleDown(ctx context.Context) error {
  var errs []error

  // 1. Operator
  errs = append(errs, p.scaleComponent(ctx, cephOperatorDeploy, 0))

  // 2. OSDs
  errs = append(errs, p.scaleByLabel(ctx, "app=rook-ceph-osd", 0)...)

  // 3. Monitors
  errs = append(errs, p.scaleByLabel(ctx, "app=rook-ceph-mon", 0)...)

  // 4. Managers
  errs = append(errs, p.scaleByLabel(ctx, "app=rook-ceph-mgr", 0)...)

  return errors.Join(errs...)
}

// ScaleUp scales Ceph components to 1 replica in reverse order:
// monitors -> managers -> OSDs -> operator.
//
// Each Rook component (mon, mgr, osd) is its own individual deployment with
// 1 replica. Rook manages the count of each component type by creating or
// deleting deployments — not by adjusting replica counts. Scaling each
// deployment back to 1 is the correct target. The Rook operator (scaled up
// last) will reconcile and recreate any missing deployments to match the
// CephCluster CR spec.
//
// If scaling one component fails, it logs a warning and continues.
// Returns a combined error of all failures for inclusion in the phase summary.
func (p *CephPhase) ScaleUp(ctx context.Context) error {
  var errs []error

  // 1. Monitors
  errs = append(errs, p.scaleByLabel(ctx, "app=rook-ceph-mon", 1)...)

  // 2. Managers
  errs = append(errs, p.scaleByLabel(ctx, "app=rook-ceph-mgr", 1)...)

  // 3. OSDs
  errs = append(errs, p.scaleByLabel(ctx, "app=rook-ceph-osd", 1)...)

  // 4. Operator
  errs = append(errs, p.scaleComponent(ctx, cephOperatorDeploy, 1))

  return errors.Join(errs...)
}

// WaitForToolsPod waits for a ready pod in the Ceph tools deployment with
// exponential backoff (1s, 2s, 4s, ... max 30s). It verifies readiness by
// executing a no-op command, not just checking deployment existence.
// The timeout is controlled by the context passed in from the caller.
func (p *CephPhase) WaitForToolsPod(ctx context.Context) error {
  maxBackoff := 30 * time.Second
  backoff := 1 * time.Second

  for {
    // Verify a pod is actually running and ready by executing a command,
    // not just checking if the deployment object exists in the API.
    _, err := p.kube.ExecInDeployment(ctx, cephNamespace, cephToolsDeploy, []string{"true"})
    if err == nil {
      p.logger.Info("ceph tools pod is ready")
      return nil
    }

    if ctx.Err() != nil {
      p.logger.Error("timed out waiting for ceph tools pod", "lastError", err)
      return ctx.Err()
    }

    p.logger.Info("waiting for ceph tools pod", "backoff", backoff, "lastError", err)
    select {
    case <-ctx.Done():
      return ctx.Err()
    case <-time.After(backoff):
    }

    backoff *= 2
    if backoff > maxBackoff {
      backoff = maxBackoff
    }
  }
}

// WaitForCephHealthy polls "ceph health" via the tools pod until the cluster
// reports HEALTH_OK or HEALTH_WARN (excluding the noout warning which is
// expected during recovery). Uses exponential backoff (2s, 4s, 8s, ... max 30s).
// The timeout is controlled by the context passed in from the caller.
func (p *CephPhase) WaitForCephHealthy(ctx context.Context) error {
  maxBackoff := 30 * time.Second
  backoff := 2 * time.Second

  for {
    output, err := p.kube.ExecInDeployment(ctx, cephNamespace, cephToolsDeploy, []string{"ceph", "health"})
    if err == nil {
      // Accept HEALTH_OK or HEALTH_WARN. During recovery, HEALTH_WARN
      // with only the noout flag is expected and safe to proceed.
      trimmed := strings.TrimSpace(output)
      if strings.HasPrefix(trimmed, "HEALTH_OK") || strings.HasPrefix(trimmed, "HEALTH_WARN") {
        p.logger.Info("ceph cluster is healthy", "status", trimmed)
        return nil
      }
      p.logger.Info("ceph cluster not yet healthy", "status", trimmed)
    } else {
      p.logger.Warn("failed to check ceph health", "error", err)
    }

    if ctx.Err() != nil {
      p.logger.Error("timed out waiting for ceph to become healthy")
      return ctx.Err()
    }

    select {
    case <-ctx.Done():
      return ctx.Err()
    case <-time.After(backoff):
    }

    backoff *= 2
    if backoff > maxBackoff {
      backoff = maxBackoff
    }
  }
}

// NeedsRecovery checks if the Ceph noout flag is set, indicating a
// previous shutdown that needs recovery.
func (p *CephPhase) NeedsRecovery(ctx context.Context) (bool, error) {
  return p.kube.IsCephNooutSet(ctx)
}

// scaleComponent scales a single named deployment, logging warnings on failure.
// Returns the error (or nil) so callers can collect it.
func (p *CephPhase) scaleComponent(ctx context.Context, name string, replicas int32) error {
  p.logger.Info("scaling deployment", "name", name, "replicas", replicas)
  if err := p.kube.ScaleDeployment(ctx, cephNamespace, name, replicas); err != nil {
    p.logger.Warn("failed to scale deployment", "name", name, "replicas", replicas, "error", err)
    return err
  }
  return nil
}

// scaleByLabel lists deployments matching the label selector and scales each one.
// Returns a slice of errors (which may contain nils) for collection by callers.
func (p *CephPhase) scaleByLabel(ctx context.Context, labelSelector string, replicas int32) []error {
  names, err := p.kube.ListDeploymentNames(ctx, cephNamespace, labelSelector)
  if err != nil {
    p.logger.Warn("failed to list deployments", "selector", labelSelector, "error", err)
    return []error{err}
  }

  var errs []error
  for _, name := range names {
    errs = append(errs, p.scaleComponent(ctx, name, replicas))
  }
  return errs
}
