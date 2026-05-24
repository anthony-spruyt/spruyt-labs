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

// CNPGPhase handles cleanup of CloudNativePG hibernation state left by older versions.
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

// Cleanup removes hibernation annotations from any CNPG clusters left hibernated
// by an older version of the orchestrator. Talos force=true bypasses PDBs entirely,
// so no new hibernation is performed; this method exists only for backward compatibility.
func (p *CNPGPhase) Cleanup(ctx context.Context) error {
	clusters, err := p.kube.GetCNPGClusters(ctx)
	if err != nil {
		if isCRDNotInstalled(err) {
			p.logger.Info("CNPG CRD not installed, skipping cleanup")
			return nil
		}
		return err
	}

	var errs []error
	for _, c := range clusters {
		if !c.Hibernated {
			continue
		}
		p.logger.Info("clearing CNPG hibernation annotation", "namespace", c.Namespace, "name", c.Name)
		if err := p.kube.SetCNPGHibernation(ctx, c.Namespace, c.Name, false); err != nil {
			p.logger.Error("failed to clear CNPG hibernation", "namespace", c.Namespace, "name", c.Name, "error", err)
			errs = append(errs, fmt.Errorf("cleanup %s/%s: %w", c.Namespace, c.Name, err))
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
