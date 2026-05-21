package main

import (
  "context"
  "fmt"
  "io"
  "log/slog"
  "slices"
  "strings"
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
  clusters          []clients.CNPGCluster
  getClustersErr    error
  getClustersBlocks bool
  // Track hibernation state changes so Wake sees hibernated=true after Hibernate
  hibernationState map[string]bool

  // Ceph config
  toolsExists        bool
  isCephNooutResult  bool
  isCephNooutErr     error
  deploymentReplicas map[string]int32
  scaleErr           error

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
  switch {
  case len(cmd) >= 4:
    m.record("ExecInDeployment:" + cmd[2] + ":" + cmd[3])
  case len(cmd) == 2 && cmd[0] == "ceph" && cmd[1] == "health":
    m.record("ExecInDeployment:ceph:health")
    return "HEALTH_OK", nil
  default:
    m.record("ExecInDeployment")
  }
  return "", nil
}

func (m *orchestratorMockKube) ScaleDeployment(ctx context.Context, ns, name string, replicas int32) error {
  m.record(fmt.Sprintf("ScaleDeployment:%s:%d", name, replicas))
  if m.scaleErr != nil {
    return m.scaleErr
  }
  return nil
}

func (m *orchestratorMockKube) ListDeploymentNames(ctx context.Context, ns, labelSelector string) ([]string, error) {
  m.record("ListDeploymentNames:" + labelSelector)
  switch labelSelector {
  case "app=rook-ceph-osd":
    return []string{"rook-ceph-osd-0", "rook-ceph-osd-1", "rook-ceph-osd-2"}, nil
  case "app=rook-ceph-mon":
    return []string{"rook-ceph-mon-a", "rook-ceph-mon-b", "rook-ceph-mon-c"}, nil
  case "app=rook-ceph-mgr":
    return []string{"rook-ceph-mgr-a", "rook-ceph-mgr-b"}, nil
  default:
    return []string{}, nil
  }
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

func (m *orchestratorMockKube) GetDeploymentReplicas(ctx context.Context, ns, name string) (int32, error) {
  m.record("GetDeploymentReplicas:" + name)
  if m.deploymentReplicas != nil {
    if r, ok := m.deploymentReplicas[ns+"/"+name]; ok {
      return r, nil
    }
  }
  return 1, nil
}

func (m *orchestratorMockKube) GetCNPGReadyInstances(ctx context.Context, ns, name string) (int, error) {
  return 0, nil
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

func (m *orchestratorMockTalos) Close() error {
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
    CephHealthWaitTimeout:    5 * time.Second,
    CephWaitToolsTimeout:     5 * time.Second,
    NodeShutdownPhaseTimeout: 5 * time.Second,
    PerNodeTimeout:           5 * time.Second,
    WorkerIPs:                []string{"198.51.100.1"},
    ControlPlaneIPs:          []string{"198.51.100.10", "198.51.100.11"},
  }

  // Ensure mock nodes include IP-to-name mappings for resolveNodeNames.
  if kube.nodes == nil {
    kube.nodes = []clients.Node{
      {Name: "ms-01-1", IP: "198.51.100.1", Ready: true},
      {Name: "e2-1", IP: "198.51.100.10", Ready: true},
      {Name: "e2-2", IP: "198.51.100.11", Ready: true},
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
      {Name: "ms-01-1", IP: "198.51.100.1", Ready: true},
      {Name: "e2-1", IP: "198.51.100.10", Ready: true},
      {Name: "e2-2", IP: "198.51.100.11", Ready: true},
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

  // Verify ordering: wait for tools pod -> Ceph scale up -> Ceph health wait -> Ceph unset noout -> CNPG wake
  toolsIdx := -1
  scaleUpIdx := -1
  healthWaitIdx := -1
  unsetNooutIdx := -1
  wakeIdx := -1

  for i, c := range calls {
    switch {
    case c == "ExecInDeployment" && toolsIdx == -1:
      toolsIdx = i
    case c == "ScaleDeployment:rook-ceph-operator:1" && scaleUpIdx == -1:
      scaleUpIdx = i
    case c == "ExecInDeployment:ceph:health" && healthWaitIdx == -1:
      healthWaitIdx = i
    case c == "ExecInDeployment:unset:noout" && unsetNooutIdx == -1:
      unsetNooutIdx = i
    case c == "SetCNPGHibernation:false" && wakeIdx == -1:
      wakeIdx = i
    }
  }

  if toolsIdx == -1 {
    t.Fatal("WaitForToolsPod was not called")
  }
  if healthWaitIdx == -1 {
    t.Fatal("Ceph health wait was not called")
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
  if scaleUpIdx != -1 && scaleUpIdx >= healthWaitIdx {
    t.Errorf("Ceph scale up (idx %d) should come before Ceph health wait (idx %d)", scaleUpIdx, healthWaitIdx)
  }
  if healthWaitIdx >= unsetNooutIdx {
    t.Errorf("Ceph health wait (idx %d) should come before Ceph unset noout (idx %d)", healthWaitIdx, unsetNooutIdx)
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
      {Name: "ms-01-1", IP: "198.51.100.1", Ready: true},
      {Name: "e2-1", IP: "198.51.100.10", Ready: true},
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
    WorkerIPs:                []string{"198.51.100.1"},
    ControlPlaneIPs:          []string{"198.51.100.10"},
  }

  orch := NewOrchestrator(cnpg, ceph, nodes, kube, cfg, logger)

  err := orch.Shutdown(context.Background())
  if err == nil {
    t.Fatal("Shutdown() should return error when CNPG phase times out")
  }

  // Ceph phases should still run even though CNPG timed out
  calls := kube.getCalls()
  if !slices.Contains(calls, "ExecInDeployment:set:noout") {
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
      {Name: "ms-01-1", IP: "198.51.100.1", Ready: true},
      {Name: "e2-1", IP: "198.51.100.10", Ready: true},
      {Name: "e2-2", IP: "198.51.100.11", Ready: true},
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

func TestOrchestratorNeedsRecoveryCNPGHibernated(t *testing.T) {
  kube := &orchestratorMockKube{
    clusters: []clients.CNPGCluster{
      {Namespace: "db", Name: "pg-main", Hibernated: true},
    },
    isCephNooutResult: false,
    toolsExists:       true,
  }
  talos := &orchestratorMockTalos{}
  orch := newTestOrchestrator(kube, talos)

  needs, err := orch.NeedsRecovery(context.Background())
  if err != nil {
    t.Fatalf("NeedsRecovery() returned error: %v", err)
  }
  if !needs {
    t.Error("NeedsRecovery() = false, want true when CNPG cluster is hibernated")
  }
}

func TestOrchestratorRecoverFromZero(t *testing.T) {
  kube := &orchestratorMockKube{
    clusters: []clients.CNPGCluster{
      {Namespace: "db", Name: "pg-main", Hibernated: true},
    },
    toolsExists: true,
    nodes: []clients.Node{
      {Name: "ms-01-1", IP: "198.51.100.1", Ready: true},
      {Name: "e2-1", IP: "198.51.100.10", Ready: true},
      {Name: "e2-2", IP: "198.51.100.11", Ready: true},
    },
  }
  talos := &orchestratorMockTalos{}
  orch := newTestOrchestrator(kube, talos)

  err := orch.RecoverFromZero(context.Background())
  if err != nil {
    t.Fatalf("RecoverFromZero() error: %v", err)
  }

  calls := kube.getCalls()

  // Verify order: ScaleUp happens BEFORE WaitForToolsPod (ExecInDeployment)
  firstScaleIdx := -1
  firstExecIdx := -1
  for i, c := range calls {
    if strings.HasPrefix(c, "ScaleDeployment:") && firstScaleIdx == -1 {
      firstScaleIdx = i
    }
    if c == "ExecInDeployment" && firstExecIdx == -1 {
      firstExecIdx = i
    }
  }

  if firstScaleIdx == -1 {
    t.Fatal("RecoverFromZero did not call ScaleDeployment")
  }
  if firstExecIdx == -1 {
    t.Fatal("RecoverFromZero did not call WaitForToolsPod (ExecInDeployment)")
  }
  if firstScaleIdx >= firstExecIdx {
    t.Errorf("ScaleUp (idx %d) must happen BEFORE WaitForToolsPod (idx %d)", firstScaleIdx, firstExecIdx)
  }

  // Verify CNPG wake also runs
  hasWake := false
  for _, c := range calls {
    if c == "SetCNPGHibernation:false" {
      hasWake = true
    }
  }
  if !hasWake {
    t.Error("RecoverFromZero should wake CNPG clusters")
  }
}

func TestOrchestratorRecoverFromZeroScaleUpFails(t *testing.T) {
  kube := &orchestratorMockKube{
    clusters:    []clients.CNPGCluster{},
    toolsExists: true,
    nodes: []clients.Node{
      {Name: "e2-1", IP: "198.51.100.10", Ready: true},
    },
    scaleErr: fmt.Errorf("scale failed"),
  }
  talos := &orchestratorMockTalos{}

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
    CephHealthWaitTimeout:    5 * time.Second,
    CephWaitToolsTimeout:     5 * time.Second,
    NodeShutdownPhaseTimeout: 5 * time.Second,
    PerNodeTimeout:           5 * time.Second,
    WorkerIPs:                []string{"198.51.100.1"},
    ControlPlaneIPs:          []string{"198.51.100.10"},
  }
  orch := NewOrchestrator(cnpg, ceph, nodes, kube, cfg, logger)

  err := orch.RecoverFromZero(context.Background())
  if err == nil {
    t.Fatal("RecoverFromZero should return error when ScaleUp fails")
  }

  // WaitForToolsPod (ExecInDeployment) should NOT be called after ScaleUp fails
  calls := kube.getCalls()
  for _, c := range calls {
    if c == "ExecInDeployment" {
      t.Error("WaitForToolsPod should not be called when ScaleUp fails")
    }
  }
}

func TestOrchestratorCephAtZeroTriggersRecovery(t *testing.T) {
  kube := &orchestratorMockKube{
    clusters:    []clients.CNPGCluster{},
    toolsExists: true,
    deploymentReplicas: map[string]int32{
      "rook-ceph/rook-ceph-operator": 0,
    },
    nodes: []clients.Node{
      {Name: "ms-01-1", IP: "198.51.100.1", Ready: true},
      {Name: "e2-1", IP: "198.51.100.10", Ready: true},
      {Name: "e2-2", IP: "198.51.100.11", Ready: true},
    },
  }
  talos := &orchestratorMockTalos{}
  orch := newTestOrchestrator(kube, talos)

  scaled, err := orch.IsCephScaledDown(context.Background())
  if err != nil {
    t.Fatalf("IsCephScaledDown() error: %v", err)
  }
  if !scaled {
    t.Error("IsCephScaledDown() = false, want true when operator at 0 replicas")
  }
}

func TestOrchestratorCephNotAtZeroSkipsEarlyRecovery(t *testing.T) {
  kube := &orchestratorMockKube{
    clusters:    []clients.CNPGCluster{},
    toolsExists: true,
    nodes: []clients.Node{
      {Name: "ms-01-1", IP: "198.51.100.1", Ready: true},
      {Name: "e2-1", IP: "198.51.100.10", Ready: true},
      {Name: "e2-2", IP: "198.51.100.11", Ready: true},
    },
  }
  talos := &orchestratorMockTalos{}
  orch := newTestOrchestrator(kube, talos)

  scaled, err := orch.IsCephScaledDown(context.Background())
  if err != nil {
    t.Fatalf("IsCephScaledDown() error: %v", err)
  }
  if scaled {
    t.Error("IsCephScaledDown() = true, want false when all Ceph running normally")
  }
}

func TestRunMonitorStartupOrderCephAtZero(t *testing.T) {
  kube := &orchestratorMockKube{
    clusters: []clients.CNPGCluster{
      {Namespace: "db", Name: "pg-main", Hibernated: true},
    },
    toolsExists: true,
    deploymentReplicas: map[string]int32{
      "rook-ceph/rook-ceph-operator": 0,
    },
    nodes: []clients.Node{
      {Name: "ms-01-1", IP: "198.51.100.1", Ready: true},
      {Name: "e2-1", IP: "198.51.100.10", Ready: true},
      {Name: "e2-2", IP: "198.51.100.11", Ready: true},
    },
  }
  talos := &orchestratorMockTalos{}
  orch := newTestOrchestrator(kube, talos)

  // Simulate runMonitor order:
  // 1. Check if Ceph scaled down
  cephDown, err := orch.IsCephScaledDown(context.Background())
  if err != nil {
    t.Fatalf("IsCephScaledDown error: %v", err)
  }
  if !cephDown {
    t.Fatal("expected Ceph to be detected as scaled down")
  }

  // 2. RecoverFromZero (not Recover!)
  err = orch.RecoverFromZero(context.Background())
  if err != nil {
    t.Fatalf("RecoverFromZero error: %v", err)
  }

  // 3. Verify recovery call order: scale-up before exec (tools wait)
  calls := kube.getCalls()
  firstScale := -1
  firstExec := -1
  for i, c := range calls {
    if strings.HasPrefix(c, "ScaleDeployment:") && strings.Contains(c, ":1") && firstScale == -1 {
      firstScale = i
    }
    if c == "ExecInDeployment" && firstExec == -1 {
      firstExec = i
    }
  }
  if firstScale == -1 {
    t.Fatal("no scale-up calls found in recovery")
  }
  if firstExec == -1 {
    t.Fatal("no exec calls found (WaitForToolsPod)")
  }
  if firstScale >= firstExec {
    t.Errorf("scale-up (idx %d) must precede tools wait (idx %d) in RecoverFromZero", firstScale, firstExec)
  }

  // 4. Verify CNPG wake was called during RecoverFromZero
  hasCNPGWake := false
  for _, c := range calls {
    if c == "SetCNPGHibernation:false" {
      hasCNPGWake = true
    }
  }
  if !hasCNPGWake {
    t.Error("RecoverFromZero should include CNPG wake")
  }
}

func TestRunMonitorStartupOrderCephRunning(t *testing.T) {
  kube := &orchestratorMockKube{
    clusters:          []clients.CNPGCluster{},
    toolsExists:       true,
    isCephNooutResult: false,
    nodes: []clients.Node{
      {Name: "ms-01-1", IP: "198.51.100.1", Ready: true},
      {Name: "e2-1", IP: "198.51.100.10", Ready: true},
      {Name: "e2-2", IP: "198.51.100.11", Ready: true},
    },
  }
  talos := &orchestratorMockTalos{}
  orch := newTestOrchestrator(kube, talos)

  cephDown, err := orch.IsCephScaledDown(context.Background())
  if err != nil {
    t.Fatalf("IsCephScaledDown error: %v", err)
  }
  if cephDown {
    t.Fatal("Ceph should not be detected as scaled down when running normally")
  }

  // NeedsRecovery also returns false
  needs, err := orch.NeedsRecovery(context.Background())
  if err != nil {
    t.Fatalf("NeedsRecovery error: %v", err)
  }
  if needs {
    t.Error("NeedsRecovery should be false when cluster is healthy")
  }
}

func TestOrchestratorNeedsRecoveryCephExecFails(t *testing.T) {
  kube := &orchestratorMockKube{
    clusters:       []clients.CNPGCluster{},
    isCephNooutErr: fmt.Errorf("no ready pods found for deployment rook-ceph/rook-ceph-tools"),
    toolsExists:    true,
  }
  talos := &orchestratorMockTalos{}
  orch := newTestOrchestrator(kube, talos)

  _, err := orch.NeedsRecovery(context.Background())
  if err == nil {
    t.Error("NeedsRecovery() should return error when Ceph exec fails")
  }
  if !strings.Contains(err.Error(), "checking ceph recovery") {
    t.Errorf("error should wrap ceph check context, got: %v", err)
  }
}

func TestOrchestratorIsCephScaledDownError(t *testing.T) {
  kube := &orchestratorMockKube{
    clusters:    []clients.CNPGCluster{},
    toolsExists: true,
    nodes: []clients.Node{
      {Name: "e2-1", IP: "198.51.100.10", Ready: true},
    },
  }
  talos := &orchestratorMockTalos{}
  orch := newTestOrchestrator(kube, talos)

  // Normal case: no error, returns false
  scaled, err := orch.IsCephScaledDown(context.Background())
  if err != nil {
    t.Fatalf("unexpected error: %v", err)
  }
  if scaled {
    t.Error("should return false when all deployments running")
  }
}
