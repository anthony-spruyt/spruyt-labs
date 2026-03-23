package phases

import (
  "context"
  "errors"
  "log/slog"

  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
  apierrors "k8s.io/apimachinery/pkg/api/errors"
  "k8s.io/apimachinery/pkg/api/meta"
)

// CNPGPhase handles hibernation and wake of CloudNativePG clusters.
type CNPGPhase struct {
  kube   clients.KubeClient
  logger *slog.Logger
}

// NewCNPGPhase creates a new CNPGPhase.
func NewCNPGPhase(kube clients.KubeClient, logger *slog.Logger) *CNPGPhase {
  return &CNPGPhase{
    kube:   kube,
    logger: logger,
  }
}

// Hibernate sets hibernation on all CNPG clusters.
// If the CNPG CRD is not installed, it logs and returns nil.
// If setting hibernation fails on a cluster, it logs the error and continues.
func (p *CNPGPhase) Hibernate(ctx context.Context) error {
  clusters, err := p.kube.GetCNPGClusters(ctx)
  if err != nil {
    if isCRDNotInstalled(err) {
      p.logger.Info("CNPG CRD not installed, skipping hibernation")
      return nil
    }
    return err
  }

  for _, c := range clusters {
    p.logger.Info("hibernating CNPG cluster", "namespace", c.Namespace, "name", c.Name)
    if err := p.kube.SetCNPGHibernation(ctx, c.Namespace, c.Name, true); err != nil {
      p.logger.Error("failed to hibernate CNPG cluster", "namespace", c.Namespace, "name", c.Name, "error", err)
      continue
    }
  }

  return nil
}

// Wake unsets hibernation on all hibernated CNPG clusters.
// If the CNPG CRD is not installed, it logs and returns nil.
// If unsetting hibernation fails on a cluster, it logs the error and continues.
func (p *CNPGPhase) Wake(ctx context.Context) error {
  clusters, err := p.kube.GetCNPGClusters(ctx)
  if err != nil {
    if isCRDNotInstalled(err) {
      p.logger.Info("CNPG CRD not installed, skipping wake")
      return nil
    }
    return err
  }

  for _, c := range clusters {
    if !c.Hibernated {
      continue
    }
    p.logger.Info("waking CNPG cluster", "namespace", c.Namespace, "name", c.Name)
    if err := p.kube.SetCNPGHibernation(ctx, c.Namespace, c.Name, false); err != nil {
      p.logger.Error("failed to wake CNPG cluster", "namespace", c.Namespace, "name", c.Name, "error", err)
      continue
    }
  }

  return nil
}

// isCRDNotInstalled checks if the error indicates the CNPG CRD is not installed.
func isCRDNotInstalled(err error) bool {
  if apierrors.IsNotFound(err) {
    return true
  }
  var noKindMatch *meta.NoKindMatchError
  return errors.As(err, &noKindMatch)
}
