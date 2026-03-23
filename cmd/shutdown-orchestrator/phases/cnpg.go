package phases

import (
  "context"
  "errors"
  "fmt"
  "log/slog"

  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
  apierrors "k8s.io/apimachinery/pkg/api/errors"
  "k8s.io/apimachinery/pkg/api/meta"
  "k8s.io/client-go/discovery"
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
// Per-cluster errors are collected and returned via errors.Join so the caller
// knows the phase did not fully succeed, while still attempting all clusters.
func (p *CNPGPhase) Hibernate(ctx context.Context) error {
  clusters, err := p.kube.GetCNPGClusters(ctx)
  if err != nil {
    if isCRDNotInstalled(err) {
      p.logger.Info("CNPG CRD not installed, skipping hibernation")
      return nil
    }
    return err
  }

  var errs []error
  for _, c := range clusters {
    p.logger.Info("hibernating CNPG cluster", "namespace", c.Namespace, "name", c.Name)
    if err := p.kube.SetCNPGHibernation(ctx, c.Namespace, c.Name, true); err != nil {
      p.logger.Error("failed to hibernate CNPG cluster", "namespace", c.Namespace, "name", c.Name, "error", err)
      errs = append(errs, fmt.Errorf("hibernate %s/%s: %w", c.Namespace, c.Name, err))
      continue
    }
  }

  return errors.Join(errs...)
}

// Wake unsets hibernation on all hibernated CNPG clusters.
// If the CNPG CRD is not installed, it logs and returns nil.
// Per-cluster errors are collected and returned via errors.Join so the caller
// knows the phase did not fully succeed, while still attempting all clusters.
func (p *CNPGPhase) Wake(ctx context.Context) error {
  clusters, err := p.kube.GetCNPGClusters(ctx)
  if err != nil {
    if isCRDNotInstalled(err) {
      p.logger.Info("CNPG CRD not installed, skipping wake")
      return nil
    }
    return err
  }

  var errs []error
  for _, c := range clusters {
    if !c.Hibernated {
      continue
    }
    p.logger.Info("waking CNPG cluster", "namespace", c.Namespace, "name", c.Name)
    if err := p.kube.SetCNPGHibernation(ctx, c.Namespace, c.Name, false); err != nil {
      p.logger.Error("failed to wake CNPG cluster", "namespace", c.Namespace, "name", c.Name, "error", err)
      errs = append(errs, fmt.Errorf("wake %s/%s: %w", c.Namespace, c.Name, err))
      continue
    }
  }

  return errors.Join(errs...)
}

// isCRDNotInstalled checks if the error indicates the CNPG CRD is not installed
// or the API group is unavailable.
func isCRDNotInstalled(err error) bool {
  if apierrors.IsNotFound(err) {
    return true
  }
  var noKindMatch *meta.NoKindMatchError
  if errors.As(err, &noKindMatch) {
    return true
  }
  // Handle partial API group discovery failure (e.g., when the API server
  // is under load and some groups are temporarily unavailable).
  var discoveryErr *discovery.ErrGroupDiscoveryFailed
  return errors.As(err, &discoveryErr)
}
