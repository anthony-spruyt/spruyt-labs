package main

import (
  "context"
  "fmt"
  "io"
  "log/slog"
  "testing"

  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
)

// mockKube implements clients.KubeClient for preflight tests.
type mockKube struct {
  nodes             []clients.Node
  getNodesErr       error
  cnpgClusters      []clients.CNPGCluster
  getCNPGErr        error
  deploymentExists  bool
  deploymentExistsE error
  execOutput        string
  execErr           error
  listDeployNames   map[string][]string // labelSelector -> names
  listDeployErr     error
}

func (m *mockKube) GetNodes(ctx context.Context) ([]clients.Node, error) {
  return m.nodes, m.getNodesErr
}
func (m *mockKube) GetCNPGClusters(ctx context.Context) ([]clients.CNPGCluster, error) {
  return m.cnpgClusters, m.getCNPGErr
}
func (m *mockKube) SetCNPGHibernation(ctx context.Context, ns, name string, hibernate bool) error {
  return nil
}
func (m *mockKube) DeploymentExists(ctx context.Context, ns, name string) (bool, error) {
  return m.deploymentExists, m.deploymentExistsE
}
func (m *mockKube) ExecInDeployment(ctx context.Context, ns, deploy string, cmd []string) (string, error) {
  return m.execOutput, m.execErr
}
func (m *mockKube) ScaleDeployment(ctx context.Context, ns, name string, replicas int32) error {
  return nil
}
func (m *mockKube) ListDeploymentNames(ctx context.Context, ns, labelSelector string) ([]string, error) {
  if m.listDeployErr != nil {
    return nil, m.listDeployErr
  }
  if m.listDeployNames != nil {
    if names, ok := m.listDeployNames[labelSelector]; ok {
      return names, nil
    }
  }
  return []string{}, nil
}
func (m *mockKube) IsCephNooutSet(ctx context.Context) (bool, error) {
  return false, nil
}

// mockTalos implements clients.TalosClient.
type mockTalos struct {
  pingErr error
}

func (m *mockTalos) Shutdown(ctx context.Context, nodeIP string, force bool) error {
  return nil
}

func (m *mockTalos) Ping(ctx context.Context, nodeIP string) error {
  return m.pingErr
}

func (m *mockTalos) Close() error { return nil }

// mockUPS implements clients.UPSClient.
type mockUPS struct {
  status    string
  statusErr error
}

func (m *mockUPS) GetStatus(ctx context.Context) (string, error) {
  return m.status, m.statusErr
}

func (m *mockUPS) Close() error { return nil }

func newDiscardLogger() *slog.Logger {
  return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func goodConfig() Config {
  return Config{
    WorkerIPs:       []string{"10.0.0.1", "10.0.0.2"},
    ControlPlaneIPs: []string{"10.0.1.1", "10.0.1.2"},
  }
}

func TestPreflightKubeAPIUnreachable(t *testing.T) {
  kube := &mockKube{
    getNodesErr:      fmt.Errorf("dial tcp 10.0.0.1:6443: connect: connection refused"),
    cnpgClusters:     []clients.CNPGCluster{},
    deploymentExists: true,
    execOutput:       "HEALTH_OK",
  }
  ups := &mockUPS{status: "OL"}
  checker := NewPreflightChecker(kube, &mockTalos{}, ups, goodConfig(), newDiscardLogger())

  results := checker.RunAll(context.Background())
  found := findResult(results, "Kubernetes API reachable")
  if found == nil {
    t.Fatal("expected 'Kubernetes API reachable' check in results")
  }
  if found.Passed {
    t.Error("expected Kubernetes API check to fail")
  }
}

func TestPreflightCNPGCRDMissing(t *testing.T) {
  kube := &mockKube{
    nodes:            []clients.Node{{Name: "node1", Ready: true}},
    getCNPGErr:       fmt.Errorf("the server could not find the requested resource: not found"),
    deploymentExists: true,
    execOutput:       "HEALTH_OK",
  }
  ups := &mockUPS{status: "OL"}
  checker := NewPreflightChecker(kube, &mockTalos{}, ups, goodConfig(), newDiscardLogger())

  results := checker.RunAll(context.Background())
  found := findResult(results, "CNPG CRD installed")
  if found == nil {
    t.Fatal("expected 'CNPG CRD installed' check in results")
  }
  if found.Passed {
    t.Error("expected CNPG CRD check to fail")
  }
}

func TestPreflightCephToolsMissing(t *testing.T) {
  kube := &mockKube{
    nodes:            []clients.Node{{Name: "node1", Ready: true}},
    cnpgClusters:     []clients.CNPGCluster{},
    deploymentExists: false,
    execOutput:       "HEALTH_OK",
  }
  ups := &mockUPS{status: "OL"}
  checker := NewPreflightChecker(kube, &mockTalos{}, ups, goodConfig(), newDiscardLogger())

  results := checker.RunAll(context.Background())
  found := findResult(results, "Ceph tools pod exists")
  if found == nil {
    t.Fatal("expected 'Ceph tools pod exists' check in results")
  }
  if found.Passed {
    t.Error("expected Ceph tools check to fail")
  }
}

func TestPreflightCephExecFails(t *testing.T) {
  kube := &mockKube{
    nodes:            []clients.Node{{Name: "node1", Ready: true}},
    cnpgClusters:     []clients.CNPGCluster{},
    deploymentExists: true,
    execErr:          fmt.Errorf("command terminated with exit code 1"),
  }
  ups := &mockUPS{status: "OL"}
  checker := NewPreflightChecker(kube, &mockTalos{}, ups, goodConfig(), newDiscardLogger())

  results := checker.RunAll(context.Background())
  found := findResult(results, "Ceph tools exec works")
  if found == nil {
    t.Fatal("expected 'Ceph tools exec works' check in results")
  }
  if found.Passed {
    t.Error("expected Ceph exec check to fail")
  }
}

func TestPreflightUPSUnreachable(t *testing.T) {
  kube := &mockKube{
    nodes:            []clients.Node{{Name: "node1", Ready: true}},
    cnpgClusters:     []clients.CNPGCluster{},
    deploymentExists: true,
    execOutput:       "HEALTH_OK",
  }
  ups := &mockUPS{statusErr: fmt.Errorf("connection refused")}
  checker := NewPreflightChecker(kube, &mockTalos{}, ups, goodConfig(), newDiscardLogger())

  results := checker.RunAll(context.Background())
  found := findResult(results, "UPS reachable")
  if found == nil {
    t.Fatal("expected 'UPS reachable' check in results")
  }
  if found.Passed {
    t.Error("expected UPS check to fail")
  }
}

func TestPreflightAllPass(t *testing.T) {
  kube := &mockKube{
    nodes:            []clients.Node{{Name: "node1", Ready: true}},
    cnpgClusters:     []clients.CNPGCluster{},
    deploymentExists: true,
    execOutput:       "HEALTH_OK",
    listDeployNames: map[string][]string{
      "app=rook-ceph-osd": {"rook-ceph-osd-0"},
      "app=rook-ceph-mon": {"rook-ceph-mon-a"},
      "app=rook-ceph-mgr": {"rook-ceph-mgr-a"},
    },
  }
  ups := &mockUPS{status: "OL"}
  checker := NewPreflightChecker(kube, &mockTalos{}, ups, goodConfig(), newDiscardLogger())

  results := checker.RunAll(context.Background())
  for _, r := range results {
    if !r.Passed {
      t.Errorf("expected all checks to pass, but %q failed: %s", r.Check, r.Error)
    }
  }
  if len(results) < 8 {
    t.Errorf("expected at least 8 checks, got %d", len(results))
  }
}

func TestPreflightTalosAPIUnreachable(t *testing.T) {
  kube := &mockKube{
    nodes:            []clients.Node{{Name: "node1", Ready: true}},
    cnpgClusters:     []clients.CNPGCluster{},
    deploymentExists: true,
    execOutput:       "HEALTH_OK",
  }
  ups := &mockUPS{status: "OL"}
  talos := &mockTalos{pingErr: fmt.Errorf("connection refused")}
  checker := NewPreflightChecker(kube, talos, ups, goodConfig(), newDiscardLogger())

  results := checker.RunAll(context.Background())
  found := findResult(results, "Talos API reachable")
  if found == nil {
    t.Fatal("expected 'Talos API reachable' check in results")
  }
  if found.Passed {
    t.Error("expected Talos API check to fail")
  }
}

func TestPreflightMultipleFails(t *testing.T) {
  kube := &mockKube{
    getNodesErr:      fmt.Errorf("connection refused"),
    getCNPGErr:       fmt.Errorf("not found"),
    deploymentExists: true,
    execErr:          fmt.Errorf("exec failed"),
  }
  ups := &mockUPS{status: "OL"}
  checker := NewPreflightChecker(kube, &mockTalos{}, ups, goodConfig(), newDiscardLogger())

  results := checker.RunAll(context.Background())
  failCount := 0
  for _, r := range results {
    if !r.Passed {
      failCount++
    }
  }
  if failCount < 3 {
    t.Errorf("expected at least 3 failures, got %d", failCount)
  }
}

func TestPreflightNodeIPsMissing(t *testing.T) {
  kube := &mockKube{
    nodes:            []clients.Node{{Name: "node1", Ready: true}},
    cnpgClusters:     []clients.CNPGCluster{},
    deploymentExists: true,
    execOutput:       "HEALTH_OK",
  }
  ups := &mockUPS{status: "OL"}
  cfg := Config{
    WorkerIPs:       []string{},
    ControlPlaneIPs: []string{},
  }
  checker := NewPreflightChecker(kube, &mockTalos{}, ups, cfg, newDiscardLogger())

  results := checker.RunAll(context.Background())
  found := findResult(results, "Node IPs configured")
  if found == nil {
    t.Fatal("expected 'Node IPs configured' check in results")
  }
  if found.Passed {
    t.Error("expected Node IPs check to fail")
  }

  // Talos API check should also fail when no IPs are configured
  talosResult := findResult(results, "Talos API reachable")
  if talosResult == nil {
    t.Fatal("expected 'Talos API reachable' check in results")
  }
  if talosResult.Passed {
    t.Error("expected Talos API check to fail when no node IPs configured")
  }
}

// findResult returns the first PreflightResult with the given check name.
func findResult(results []PreflightResult, name string) *PreflightResult {
  for _, r := range results {
    if r.Check == name {
      return &r
    }
  }
  return nil
}
