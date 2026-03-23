package main

import (
  "context"
  "fmt"
  "log/slog"
  "strings"

  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
)

// PreflightResult captures the outcome of a single preflight check.
type PreflightResult struct {
  Check  string
  Passed bool
  Error  string
}

// PreflightChecker runs all preflight checks before shutdown orchestration.
type PreflightChecker struct {
  kube   clients.KubeClient
  talos  clients.TalosClient
  ups    clients.UPSClient
  cfg    Config
  logger *slog.Logger
}

// NewPreflightChecker creates a PreflightChecker with the given dependencies.
func NewPreflightChecker(
  kube clients.KubeClient,
  talos clients.TalosClient,
  ups clients.UPSClient,
  cfg Config,
  logger *slog.Logger,
) *PreflightChecker {
  return &PreflightChecker{
    kube:   kube,
    talos:  talos,
    ups:    ups,
    cfg:    cfg,
    logger: logger,
  }
}

// RunAll executes every preflight check and returns all results.
// It does not stop on the first failure.
func (p *PreflightChecker) RunAll(ctx context.Context) []PreflightResult {
  var results []PreflightResult

  // 1. Kubernetes API reachable
  _, err := p.kube.GetNodes(ctx)
  results = append(results, makeResult("Kubernetes API reachable", err))

  // 2. CNPG CRD installed
  _, err = p.kube.GetCNPGClusters(ctx)
  results = append(results, makeResult("CNPG CRD installed", err))

  // 3. Ceph tools pod exists
  exists, err := p.kube.DeploymentExists(ctx, "rook-ceph", "rook-ceph-tools")
  if err != nil {
    results = append(results, makeResult("Ceph tools pod exists", err))
  } else if !exists {
    results = append(results, PreflightResult{
      Check:  "Ceph tools pod exists",
      Passed: false,
      Error:  "deployment rook-ceph-tools not found in rook-ceph namespace",
    })
  } else {
    results = append(results, PreflightResult{
      Check:  "Ceph tools pod exists",
      Passed: true,
    })
  }

  // 4. Ceph tools exec works
  _, err = p.kube.ExecInDeployment(ctx, "rook-ceph", "rook-ceph-tools", []string{"ceph", "status"})
  results = append(results, makeResult("Ceph tools exec works", err))

  // 5. Node IPs configured
  if len(p.cfg.WorkerIPs) == 0 || len(p.cfg.ControlPlaneIPs) == 0 {
    results = append(results, PreflightResult{
      Check:  "Node IPs configured",
      Passed: false,
      Error:  "WorkerIPs and ControlPlaneIPs must both be non-empty",
    })
  } else {
    results = append(results, PreflightResult{
      Check:  "Node IPs configured",
      Passed: true,
    })
  }

  // 6. Talos API reachable (check each node)
  allNodeIPs := append(append([]string{}, p.cfg.WorkerIPs...), p.cfg.ControlPlaneIPs...)
  talosOK := true
  var talosErrs []string
  for _, ip := range allNodeIPs {
    if pingErr := p.talos.Ping(ctx, ip); pingErr != nil {
      talosOK = false
      talosErrs = append(talosErrs, fmt.Sprintf("%s: %v", ip, pingErr))
    }
  }
  if talosOK {
    results = append(results, PreflightResult{Check: "Talos API reachable", Passed: true})
  } else {
    results = append(results, PreflightResult{
      Check:  "Talos API reachable",
      Passed: false,
      Error:  fmt.Sprintf("unreachable nodes: %s", strings.Join(talosErrs, "; ")),
    })
  }

  // 7. UPS reachable
  _, err = p.ups.GetStatus(ctx)
  results = append(results, makeResult("UPS reachable", err))

  return results
}

func makeResult(check string, err error) PreflightResult {
  if err != nil {
    return PreflightResult{
      Check:  check,
      Passed: false,
      Error:  err.Error(),
    }
  }
  return PreflightResult{
    Check:  check,
    Passed: true,
  }
}
