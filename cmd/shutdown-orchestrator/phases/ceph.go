package phases

import (
  "context"
  "encoding/json"
  "errors"
  "fmt"
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
  kube          clients.KubeClient
  logger        *slog.Logger
  healthBackoff time.Duration
}

// NewCephPhase creates a new CephPhase.
func NewCephPhase(kube clients.KubeClient, logger *slog.Logger) *CephPhase {
  return &CephPhase{
    kube:          kube,
    logger:        logger,
    healthBackoff: 2 * time.Second,
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
// operator -> MDSs -> OSDs -> monitors -> managers
// per Rook node-maintenance docs: https://rook.io/docs/rook/latest/Upgrade/node-maintenance/
//
// If scaling one component fails, it logs a warning and continues.
// Returns a combined error of all failures for inclusion in the phase summary.
func (p *CephPhase) ScaleDown(ctx context.Context) error {
  var errs []error

  if err := p.scaleComponent(ctx, cephOperatorDeploy, 0); err != nil {
    errs = append(errs, err)
  }
  if ctx.Err() != nil {
    return errors.Join(append(errs, ctx.Err())...)
  }

  errs = append(errs, p.scaleByLabel(ctx, "app=rook-ceph-mds", 0)...)
  if ctx.Err() != nil {
    return errors.Join(append(errs, ctx.Err())...)
  }

  errs = append(errs, p.scaleByLabel(ctx, "app=rook-ceph-osd", 0)...)
  if ctx.Err() != nil {
    return errors.Join(append(errs, ctx.Err())...)
  }

  errs = append(errs, p.scaleByLabel(ctx, "app=rook-ceph-mon", 0)...)
  if ctx.Err() != nil {
    return errors.Join(append(errs, ctx.Err())...)
  }

  errs = append(errs, p.scaleByLabel(ctx, "app=rook-ceph-mgr", 0)...)

  return errors.Join(errs...)
}

// ScaleUp scales Ceph components to 1 replica in reverse order:
// monitors -> managers -> OSDs -> MDSs -> operator
// per Rook node-maintenance docs: https://rook.io/docs/rook/latest/Upgrade/node-maintenance/
//
// Each Rook component (mon, mgr, osd) is its own individual deployment with
// 1 replica. Rook manages the count of each component type by creating or
// deleting deployments — not by adjusting replica counts. Scaling each
// deployment back to 1 is the correct target. The Rook operator (scaled up
// last) will reconcile and recreate any missing deployments to match the
// CephCluster CR spec.
//
// Unlike ScaleDown, this does not check ctx.Err() between steps because
// recovery runs without UPS budget pressure — best effort to restore all
// components even if the context is near expiry.
//
// If scaling one component fails, it logs a warning and continues.
// Returns a combined error of all failures for inclusion in the phase summary.
func (p *CephPhase) ScaleUp(ctx context.Context) error {
  var errs []error

  errs = append(errs, p.scaleByLabel(ctx, "app=rook-ceph-mon", 1)...)
  errs = append(errs, p.scaleByLabel(ctx, "app=rook-ceph-mgr", 1)...)
  errs = append(errs, p.scaleByLabel(ctx, "app=rook-ceph-osd", 1)...)
  errs = append(errs, p.scaleByLabel(ctx, "app=rook-ceph-mds", 1)...)

  if err := p.scaleComponent(ctx, cephOperatorDeploy, 1); err != nil {
    errs = append(errs, err)
  }

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
    timer := time.NewTimer(backoff)
    select {
    case <-ctx.Done():
      timer.Stop()
      return ctx.Err()
    case <-timer.C:
    }

    backoff *= 2
    if backoff > maxBackoff {
      backoff = maxBackoff
    }
  }
}

// WaitForCephHealthy polls "ceph health" via the tools pod until the cluster
// reports HEALTH_OK, or every OSD is up at any other health level: noout only
// concerns OSDs, so a lasting warning or error elsewhere (a failed mgr module)
// must not keep it set. Any OSD down, exec errors and unparsable output keep it polling.
// Uses exponential backoff (2s, 4s, 8s, ... max 30s).
// The timeout is controlled by the context passed in from the caller.
func (p *CephPhase) WaitForCephHealthy(ctx context.Context) error {
  maxBackoff := 30 * time.Second
  backoff := p.healthBackoff

  for {
    output, err := p.kube.ExecInDeployment(ctx, cephNamespace, cephToolsDeploy, []string{"ceph", "health"})
    if err == nil {
      trimmed := strings.TrimSpace(output)
      if strings.HasPrefix(trimmed, "HEALTH_OK") {
        p.logger.Info("ceph cluster is healthy", "status", trimmed)
        return nil
      }
      allUp, upErr := p.allOSDsUp(ctx)
      switch {
      case upErr != nil:
        p.logger.Warn("failed to check ceph osd status", "error", upErr)
      case allUp:
        p.logger.Warn("ceph cluster is not HEALTH_OK but every osd is up, proceeding with recovery",
          "status", trimmed)
        return nil
      default:
        p.logger.Info("ceph cluster has osds down", "status", trimmed)
      }
    } else {
      p.logger.Warn("failed to check ceph health", "error", err)
    }

    if ctx.Err() != nil {
      p.logger.Error("timed out waiting for ceph to become healthy")
      return ctx.Err()
    }

    timer := time.NewTimer(backoff)
    select {
    case <-ctx.Done():
      timer.Stop()
      return ctx.Err()
    case <-timer.C:
    }

    backoff *= 2
    if backoff > maxBackoff {
      backoff = maxBackoff
    }
  }
}

// allOSDsUp reports whether the cluster has OSDs and every one of them is up.
func (p *CephPhase) allOSDsUp(ctx context.Context) (bool, error) {
  output, err := p.kube.ExecInDeployment(ctx, cephNamespace, cephToolsDeploy, []string{"ceph", "osd", "stat", "-f", "json"})
  if err != nil {
    return false, err
  }

  var stat struct {
    NumOSDs   int `json:"num_osds"`
    NumUpOSDs int `json:"num_up_osds"`
  }
  if err := json.Unmarshal([]byte(output), &stat); err != nil {
    return false, fmt.Errorf("parsing ceph osd stat JSON: %w", err)
  }
  return stat.NumOSDs > 0 && stat.NumUpOSDs == stat.NumOSDs, nil
}

// NeedsRecovery checks if the Ceph noout flag is set, indicating a
// previous shutdown that needs recovery.
func (p *CephPhase) NeedsRecovery(ctx context.Context) (bool, error) {
  return p.kube.IsCephNooutSet(ctx)
}

// IsCephScaledDown checks if Ceph deployments are at 0 replicas, indicating a
// previous orchestrator shutdown that needs recovery. This uses only the
// Kubernetes API (no Ceph exec required) so it works even when Ceph is down.
//
// Returns true if the operator OR any MON/OSD/MDS deployment is at 0 replicas.
func (p *CephPhase) IsCephScaledDown(ctx context.Context) (bool, error) {
  operatorReplicas, err := p.kube.GetDeploymentReplicas(ctx, cephNamespace, cephOperatorDeploy)
  if err != nil {
    return false, fmt.Errorf("checking operator replicas: %w", err)
  }
  if operatorReplicas == 0 {
    p.logger.Info("ceph operator is at 0 replicas, shutdown recovery needed")
    return true, nil
  }

  monNames, err := p.kube.ListDeploymentNames(ctx, cephNamespace, "app=rook-ceph-mon")
  if err != nil {
    return false, fmt.Errorf("listing mon deployments: %w", err)
  }
  for _, name := range monNames {
    replicas, err := p.kube.GetDeploymentReplicas(ctx, cephNamespace, name)
    if err != nil {
      return false, fmt.Errorf("checking mon %s replicas: %w", name, err)
    }
    if replicas == 0 {
      p.logger.Info("ceph mon at 0 replicas, shutdown recovery needed", "deployment", name)
      return true, nil
    }
  }

  osdNames, err := p.kube.ListDeploymentNames(ctx, cephNamespace, "app=rook-ceph-osd")
  if err != nil {
    return false, fmt.Errorf("listing osd deployments: %w", err)
  }
  for _, name := range osdNames {
    replicas, err := p.kube.GetDeploymentReplicas(ctx, cephNamespace, name)
    if err != nil {
      return false, fmt.Errorf("checking osd %s replicas: %w", name, err)
    }
    if replicas == 0 {
      p.logger.Info("ceph osd at 0 replicas, shutdown recovery needed", "deployment", name)
      return true, nil
    }
  }

  mdsNames, err := p.kube.ListDeploymentNames(ctx, cephNamespace, "app=rook-ceph-mds")
  if err != nil {
    return false, fmt.Errorf("listing mds deployments: %w", err)
  }
  for _, name := range mdsNames {
    replicas, err := p.kube.GetDeploymentReplicas(ctx, cephNamespace, name)
    if err != nil {
      return false, fmt.Errorf("checking mds %s replicas: %w", name, err)
    }
    if replicas == 0 {
      p.logger.Info("ceph mds at 0 replicas, shutdown recovery needed", "deployment", name)
      return true, nil
    }
  }

  return false, nil
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
// Returns a slice of non-nil errors for collection by callers.
func (p *CephPhase) scaleByLabel(ctx context.Context, labelSelector string, replicas int32) []error {
  names, err := p.kube.ListDeploymentNames(ctx, cephNamespace, labelSelector)
  if err != nil {
    p.logger.Warn("failed to list deployments", "selector", labelSelector, "error", err)
    return []error{err}
  }

  var errs []error
  for _, name := range names {
    if err := p.scaleComponent(ctx, name, replicas); err != nil {
      errs = append(errs, err)
    }
  }
  return errs
}
