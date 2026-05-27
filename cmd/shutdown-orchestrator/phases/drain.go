package phases

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
)

// DrainPhase handles cordoning nodes and evicting workloads before Ceph scale-down.
// This ensures kernel RBD mounts are cleanly released before Ceph is shut down,
// preventing the infinite reboot-shutdown loop caused by blocked unmounts.
type DrainPhase struct {
	kube   clients.KubeClient
	logger *slog.Logger
}

// NewDrainPhase creates a new DrainPhase.
func NewDrainPhase(kube clients.KubeClient, logger *slog.Logger) *DrainPhase {
	return &DrainPhase{kube: kube, logger: logger}
}

// CordonWorkers marks each worker node as unschedulable to prevent pod rescheduling.
func (p *DrainPhase) CordonWorkers(ctx context.Context, workerNames []string) error {
	for _, name := range workerNames {
		p.logger.Info("cordoning node", "name", name)
		if err := p.kube.CordonNode(ctx, name); err != nil {
			return err
		}
	}
	return nil
}

// EvictWorkloads deletes non-DaemonSet pods (excluding specified namespaces) from
// worker nodes and waits for them to terminate. Excluded namespaces (rook-ceph,
// kube-system, nut-system) contain pods that must remain running during drain.
func (p *DrainPhase) EvictWorkloads(ctx context.Context, workerNames []string, excludeNamespaces []string, gracePeriod int64) error {
	excludeSet := make(map[string]bool, len(excludeNamespaces))
	for _, ns := range excludeNamespaces {
		excludeSet[ns] = true
	}

	for _, nodeName := range workerNames {
		pods, err := p.kube.GetPodsOnNode(ctx, nodeName)
		if err != nil {
			return fmt.Errorf("getting pods on node %s: %w", nodeName, err)
		}
		for _, pod := range pods {
			if excludeSet[pod.Namespace] || pod.DaemonSet {
				continue
			}
			p.logger.Info("deleting pod", "namespace", pod.Namespace, "name", pod.Name, "node", nodeName)
			if err := p.kube.DeletePod(ctx, pod.Namespace, pod.Name, gracePeriod); err != nil {
				p.logger.Warn("failed to delete pod", "namespace", pod.Namespace, "name", pod.Name, "error", err)
			}
		}
	}

	return p.waitForPodsGone(ctx, workerNames, excludeSet)
}

// UncordonWorkers marks each worker node as schedulable again after recovery.
func (p *DrainPhase) UncordonWorkers(ctx context.Context, workerNames []string) error {
	for _, name := range workerNames {
		p.logger.Info("uncordoning node", "name", name)
		if err := p.kube.UncordonNode(ctx, name); err != nil {
			return err
		}
	}
	return nil
}

// waitForPodsGone polls until no evictable pods remain on the given nodes.
func (p *DrainPhase) waitForPodsGone(ctx context.Context, workerNames []string, excludeSet map[string]bool) error {
	pollInterval := 5 * time.Second
	for {
		remaining := 0
		for _, nodeName := range workerNames {
			pods, err := p.kube.GetPodsOnNode(ctx, nodeName)
			if err != nil {
				p.logger.Warn("error listing pods during drain wait", "node", nodeName, "error", err)
				continue
			}
			for _, pod := range pods {
				if !excludeSet[pod.Namespace] && !pod.DaemonSet {
					remaining++
					p.logger.Info("waiting for pod termination", "namespace", pod.Namespace, "name", pod.Name, "node", nodeName)
				}
			}
		}
		if remaining == 0 {
			p.logger.Info("all evictable pods terminated")
			return nil
		}
		p.logger.Info("waiting for pods to terminate", "remaining", remaining)
		timer := time.NewTimer(pollInterval)
		select {
		case <-ctx.Done():
			timer.Stop()
			return fmt.Errorf("drain timed out with %d pods still running: %w", remaining, ctx.Err())
		case <-timer.C:
		}
	}
}
