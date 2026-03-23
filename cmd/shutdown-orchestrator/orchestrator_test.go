package main

import (
  "context"
  "fmt"
  "io"
  "log/slog"
  "sync"
  "testing"
  "time"

  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/phases"
)

// orchestratorMockKube implements clients.KubeClient and records call order.
type orchestratorMockKube struct {
  mu    sync.Mutex
  calls []string

  // CNPG config
  clusters       []clients.CNPGCluster
  getClustersErr error
  getClustersBlocks bool
  // Track hibernation state changes so Wake sees hibernated=true after Hibernate
  hibernationState map[string]bool

  // Ceph config
  toolsExists       bool
  isCephNooutResult bool
  isCephNooutErr    error

  // Node config
  nodes    []clients.Node
  nodesErr error
}

func (m *orchestratorMockKube) record(name string) {
  m.mu.Lock()
  defer m.mu.Unlock()
  m.calls = append(m.calls, name)
}

func (m *orchestratorMockKube) getCalls() []string {
  m.mu.Lock()
  defer m.mu.Unlock()
  out := make([]string, len(m.calls))
  copy(out, m.calls)
  return out
}

func (m *orchestratorMockKube) GetCNPGClusters(ctx context.Context) ([]clients.CNPGCluster, error) {
  if m.getClustersBlocks {
    <-ctx.Done()
    return nil, ctx.Err()
  }
  m.record("GetCNPGClusters")
  if m.getClustersErr != nil {
    return nil, m.getClustersErr
  }
  // Return clusters with current hibernation state
  m.mu.Lock()
  result := make([]clients.CNPGCluster, len(m.clusters))
  for i, c := range m.clusters {
    result[i] = c
    if m.hibernationState != nil {
      if state, ok := m.hibernationState[c.Namespace+"/"+c.Name]; ok {
        result[i].Hibernated = state
      }
    }
  }
  m.mu.Unlock()
  return result, nil
}

func (m *orchestratorMockKube) SetCNPGHibernation(ctx context.Context, ns, name string, hibernate bool) error {
  if hibernate {
    m.record("SetCNPGHibernation:true")
  } else {
    m.record("SetCNPGHibernation:false")
  }
  // Track state change
  m.mu.Lock()
  if m.hibernationState == nil {
    m.hibernationState = make(map[string]bool)
  }
  m.hibernationState[ns+"/"+name] = hibernate
  m.mu.Unlock()
  return nil
}

func (m *orchestratorMockKube) DeploymentExists(ctx context.Context, ns, name string) (bool, error) {
  m.record("DeploymentExists:" + name)
  return m.toolsExists, nil
}

func (m *orchestratorMockKube) ExecInDeployment(ctx context.Context, ns, deploy string, cmd []string) (string, error) {
  if len(cmd) >= 4 {
    m.record("ExecInDeployment:" + cmd[2] + ":" + cmd[3])
  } else {
    m.record("ExecInDeployment")
  }
  return "", nil
}

func (m *orchestratorMockKube) ScaleDeployment(ctx context.Context, ns, name string, replicas int32) error {
  m.record(fmt.Sprintf("ScaleDeployment:%s:%d", name, replicas))
  return nil
}

func (m *orchestratorMockKube) ListDeploymentNames(ctx context.Context, ns, labelSelector string) ([]string, error) {
  return []string{}, nil
}

func (m *orchestratorMockKube) GetNodes(ctx context.Context) ([]clients.Node, error) {
  m.record("GetNodes")
  if m.nodesErr != nil {
    return nil, m.nodesErr
  }
  return m.nodes, nil
}

func (m *orchestratorMockKube) IsCephNooutSet(ctx context.Context) (bool, error) {
  m.record("IsCephNooutSet")
  return m.isCephNooutResult, m.isCephNooutErr
}

// orchestratorMockTalos implements clients.TalosClient.
type orchestratorMockTalos struct {
  mu    sync.Mutex
  calls []string
}

func (m *orchestratorMockTalos) Shutdown(ctx context.Context, nodeIP string, force bool) error {
  m.mu.Lock()
  defer m.mu.Unlock()
  m.calls = append(m.calls, "Shutdown:"+nodeIP)
  return nil
}

func (m *orchestratorMockTalos) Ping(ctx context.Context, nodeIP string) error {
  return nil
}

func (m *orchestratorMockTalos) getCalls() []string {
  m.mu.Lock()
  defer m.mu.Unlock()
  out := make([]string, len(m.calls))
  copy(out, m.calls)
  return out
}

func discardLogger() *slog.Logger {
  return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func newTestOrchestrator(kube *orchestratorMockKube, talos *orchestratorMockTalos) *Orchestrator {
  logger := discardLogger()
  cnpg := phases.NewCNPGPhase(kube, logger)
  ceph := phases.NewCephPhase(kube, logger)
  nodes := phases.NewNodePhase(talos, logger)

  cfg := Config{
    Mode:                     "test",
    NodeName:                 "e2-1",
    CNPGPhaseTimeout:         5 * time.Second,
    CephFlagPhaseTimeout:     5 * time.Second,
    CephScalePhaseTimeout:    5 * time.Second,
    CephWaitToolsTimeout:     5 * time.Second,
    NodeShutdownPhaseTimeout: 5 * time.Second,
    PerNodeTimeout:           5 * time.Second,
    WorkerIPs:                []string{"10.0.0.1"},
    ControlPlaneIPs:          []string{"10.0.0.10", "10.0.0.11"},
  }

  // Ensure mock nodes include IP-to-name mappings for resolveNodeNames.
  if kube.nodes == nil {
    kube.nodes = []clients.Node{
      {Name: "ms-01-1", IP: "10.0.0.1", Ready: true},
      {Name: "e2-1", IP: "10.0.0.10", Ready: true},
      {Name: "e2-2", IP: "10.0.0.11", Ready: true},
    }
  }

  return NewOrchestrator(cnpg, ceph, nodes, kube, cfg, logger)
}

func TestOrchestratorShutdownSequence(t *testing.T) {
  kube := &orchestratorMockKube{
    clusters: []clients.CNPGCluster{
      {Namespace: "db", Name: "pg-main", Hibernated: false},
    },
    toolsExists: true,
    nodes: []clients.Node{
      {Name: "ms-01-1", IP: "10.0.0.1", Ready: true},
      {Name: "e2-1", IP: "10.0.0.10", Ready: true},
      {Name: "e2-2", IP: "10.0.0.11", Ready: true},
    },
  }
  talos := &orchestratorMockTalos{}
  orch := newTestOrchestrator(kube, talos)

  err := orch.Shutdown(context.Background())
  if err != nil {
    t.Fatalf("Shutdown() returned error: %v", err)
  }

  calls := kube.getCalls()

  // Verify ordering: CNPG hibernate before Ceph noout before Ceph scale down before node shutdown
  cnpgIdx := -1
  cephNooutIdx := -1
  cephScaleIdx := -1

  for i, c := range calls {
    switch {
    case c == "SetCNPGHibernation:true" && cnpgIdx == -1:
      cnpgIdx = i
    case c == "ExecInDeployment:set:noout" && cephNooutIdx == -1:
      cephNooutIdx = i
    case c == "ScaleDeployment:rook-ceph-operator:0" && cephScaleIdx == -1:
      cephScaleIdx = i
    }
  }

  if cnpgIdx == -1 {
    t.Fatal("CNPG hibernate was not called")
  }
  if cephNooutIdx == -1 {
    t.Fatal("Ceph set noout was not called")
  }
  if cephScaleIdx == -1 {
    // Scale down calls operator first; if no deployments listed by label,
    // only operator scale is called
    t.Fatal("Ceph scale down was not called")
  }

  if cnpgIdx >= cephNooutIdx {
    t.Errorf("CNPG hibernate (idx %d) should come before Ceph set noout (idx %d)", cnpgIdx, cephNooutIdx)
  }
  if cephNooutIdx >= cephScaleIdx {
    t.Errorf("Ceph set noout (idx %d) should come before Ceph scale down (idx %d)", cephNooutIdx, cephScaleIdx)
  }

  // Verify talos shutdown was called
  talosCalls := talos.getCalls()
  if len(talosCalls) == 0 {
    t.Fatal("node shutdown was not called via Talos")
  }
}

func TestOrchestratorRecoverySequence(t *testing.T) {
  kube := &orchestratorMockKube{
    clusters: []clients.CNPGCluster{
      {Namespace: "db", Name: "pg-main", Hibernated: true},
    },
    toolsExists: true,
    nodes: []clients.Node{
      {Name: "cp-1", Ready: true},
    },
  }
  talos := &orchestratorMockTalos{}
  orch := newTestOrchestrator(kube, talos)

  err := orch.Recover(context.Background())
  if err != nil {
    t.Fatalf("Recover() returned error: %v", err)
  }

  calls := kube.getCalls()

  // Verify ordering: wait for tools pod -> Ceph scale up -> Ceph unset noout -> CNPG wake
  toolsIdx := -1
  scaleUpIdx := -1
  unsetNooutIdx := -1
  wakeIdx := -1

  for i, c := range calls {
    switch {
    case c == "DeploymentExists:rook-ceph-tools" && toolsIdx == -1:
      toolsIdx = i
    case c == "ScaleDeployment:rook-ceph-operator:1" && scaleUpIdx == -1:
      // ScaleUp calls operator last but we just need some scale-up call
      scaleUpIdx = i
    case c == "ExecInDeployment:unset:noout" && unsetNooutIdx == -1:
      unsetNooutIdx = i
    case c == "SetCNPGHibernation:false" && wakeIdx == -1:
      wakeIdx = i
    }
  }

  if toolsIdx == -1 {
    t.Fatal("WaitForToolsPod was not called")
  }
  if unsetNooutIdx == -1 {
    t.Fatal("Ceph unset noout was not called")
  }
  if wakeIdx == -1 {
    t.Fatal("CNPG wake was not called")
  }

  if toolsIdx >= unsetNooutIdx {
    t.Errorf("WaitForToolsPod (idx %d) should come before Ceph unset noout (idx %d)", toolsIdx, unsetNooutIdx)
  }
  if unsetNooutIdx >= wakeIdx {
    t.Errorf("Ceph unset noout (idx %d) should come before CNPG wake (idx %d)", unsetNooutIdx, wakeIdx)
  }
}

func TestOrchestratorPhaseTimeout(t *testing.T) {
  kube := &orchestratorMockKube{
    getClustersBlocks: true, // CNPG will block forever
    toolsExists:       true,
    nodes: []clients.Node{
      {Name: "ms-01-1", IP: "10.0.0.1", Ready: true},
      {Name: "e2-1", IP: "10.0.0.10", Ready: true},
    },
  }
  talos := &orchestratorMockTalos{}
  logger := discardLogger()
  cnpg := phases.NewCNPGPhase(kube, logger)
  ceph := phases.NewCephPhase(kube, logger)
  nodes := phases.NewNodePhase(talos, logger)

  cfg := Config{
    Mode:                     "test",
    NodeName:                 "e2-1",
    CNPGPhaseTimeout:         100 * time.Millisecond, // Short timeout
    CephFlagPhaseTimeout:     5 * time.Second,
    CephScalePhaseTimeout:    5 * time.Second,
    NodeShutdownPhaseTimeout: 5 * time.Second,
    WorkerIPs:                []string{"10.0.0.1"},
    ControlPlaneIPs:          []string{"10.0.0.10"},
  }

  orch := NewOrchestrator(cnpg, ceph, nodes, kube, cfg, logger)

  err := orch.Shutdown(context.Background())
  if err == nil {
    t.Fatal("Shutdown() should return error when CNPG phase times out")
  }

  // Ceph phases should still run even though CNPG timed out
  calls := kube.getCalls()
  foundCeph := false
  for _, c := range calls {
    if c == "ExecInDeployment:set:noout" {
      foundCeph = true
      break
    }
  }
  if !foundCeph {
    t.Error("Ceph set noout should still run after CNPG phase timeout")
  }

  // Talos should still run
  talosCalls := talos.getCalls()
  if len(talosCalls) == 0 {
    t.Error("node shutdown should still run after CNPG phase timeout")
  }
}

func TestOrchestratorNeedsRecoveryCephNoout(t *testing.T) {
  kube := &orchestratorMockKube{
    clusters:          []clients.CNPGCluster{},
    isCephNooutResult: true,
    toolsExists:       true,
  }
  talos := &orchestratorMockTalos{}
  orch := newTestOrchestrator(kube, talos)

  needs, err := orch.NeedsRecovery(context.Background())
  if err != nil {
    t.Fatalf("NeedsRecovery() returned error: %v", err)
  }
  if !needs {
    t.Error("NeedsRecovery() = false, want true when Ceph noout is set")
  }
}

func TestOrchestratorNeedsRecoveryFalse(t *testing.T) {
  kube := &orchestratorMockKube{
    clusters:          []clients.CNPGCluster{},
    isCephNooutResult: false,
    toolsExists:       true,
  }
  talos := &orchestratorMockTalos{}
  orch := newTestOrchestrator(kube, talos)

  needs, err := orch.NeedsRecovery(context.Background())
  if err != nil {
    t.Fatalf("NeedsRecovery() returned error: %v", err)
  }
  if needs {
    t.Error("NeedsRecovery() = true, want false when no recovery signals present")
  }
}

func TestOrchestratorTestMode(t *testing.T) {
  kube := &orchestratorMockKube{
    clusters: []clients.CNPGCluster{
      {Namespace: "db", Name: "pg-main", Hibernated: false},
    },
    toolsExists: true,
    nodes: []clients.Node{
      {Name: "ms-01-1", IP: "10.0.0.1", Ready: true},
      {Name: "e2-1", IP: "10.0.0.10", Ready: true},
      {Name: "e2-2", IP: "10.0.0.11", Ready: true},
    },
  }
  talos := &orchestratorMockTalos{}
  orch := newTestOrchestrator(kube, talos)

  err := orch.RunTest(context.Background())
  if err != nil {
    t.Fatalf("RunTest() returned error: %v", err)
  }

  calls := kube.getCalls()

  // Should see both hibernate and wake calls (shutdown then recovery)
  foundHibernate := false
  foundWake := false
  hibernateIdx := -1
  wakeIdx := -1

  for i, c := range calls {
    switch {
    case c == "SetCNPGHibernation:true" && !foundHibernate:
      foundHibernate = true
      hibernateIdx = i
    case c == "SetCNPGHibernation:false" && !foundWake:
      foundWake = true
      wakeIdx = i
    }
  }

  if !foundHibernate {
    t.Error("RunTest() should call CNPG hibernate (shutdown phase)")
  }
  if !foundWake {
    t.Error("RunTest() should call CNPG wake (recovery phase)")
  }
  if foundHibernate && foundWake && hibernateIdx >= wakeIdx {
    t.Errorf("hibernate (idx %d) should come before wake (idx %d)", hibernateIdx, wakeIdx)
  }
}
