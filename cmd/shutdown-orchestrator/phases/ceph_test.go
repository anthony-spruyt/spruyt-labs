package phases

import (
  "context"
  "fmt"
  "log/slog"
  "os"
  "strings"
  "testing"

  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
)

// mockCephKubeClient implements clients.KubeClient for testing Ceph phases.
type mockCephKubeClient struct {
  // Call tracking
  deploymentExistsCalls   []deploymentExistsCall
  execInDeploymentCalls   []execInDeploymentCall
  scaleDeploymentCalls    []scaleDeploymentCall
  listDeploymentCalls     []listDeploymentCall
  isCephNooutSetCalls     int

  // Configurable return values
  deploymentExistsResult  map[string]bool
  deploymentExistsErr     map[string]error
  execInDeploymentResult  map[string]string
  execInDeploymentErr     map[string]error
  scaleDeploymentErr      map[string]error
  listDeploymentResult    map[string][]string
  listDeploymentErr       map[string]error
  isCephNooutSetResult    bool
  isCephNooutSetErr       error
}

type deploymentExistsCall struct {
  Ns, Name string
}

type execInDeploymentCall struct {
  Ns, Deploy string
  Cmd        []string
}

type scaleDeploymentCall struct {
  Ns, Name string
  Replicas int32
}

type listDeploymentCall struct {
  Ns, LabelSelector string
}

func newMockCephKubeClient() *mockCephKubeClient {
  return &mockCephKubeClient{
    deploymentExistsResult: make(map[string]bool),
    deploymentExistsErr:    make(map[string]error),
    execInDeploymentResult: make(map[string]string),
    execInDeploymentErr:    make(map[string]error),
    scaleDeploymentErr:     make(map[string]error),
    listDeploymentResult:   make(map[string][]string),
    listDeploymentErr:      make(map[string]error),
  }
}

func (m *mockCephKubeClient) DeploymentExists(ctx context.Context, ns, name string) (bool, error) {
  m.deploymentExistsCalls = append(m.deploymentExistsCalls, deploymentExistsCall{ns, name})
  key := ns + "/" + name
  if err, ok := m.deploymentExistsErr[key]; ok {
    return false, err
  }
  if result, ok := m.deploymentExistsResult[key]; ok {
    return result, nil
  }
  return true, nil
}

func (m *mockCephKubeClient) ExecInDeployment(ctx context.Context, ns, deploy string, cmd []string) (string, error) {
  m.execInDeploymentCalls = append(m.execInDeploymentCalls, execInDeploymentCall{ns, deploy, cmd})
  key := ns + "/" + deploy
  if err, ok := m.execInDeploymentErr[key]; ok {
    return "", err
  }
  if result, ok := m.execInDeploymentResult[key]; ok {
    return result, nil
  }
  return "", nil
}

func (m *mockCephKubeClient) ScaleDeployment(ctx context.Context, ns, name string, replicas int32) error {
  m.scaleDeploymentCalls = append(m.scaleDeploymentCalls, scaleDeploymentCall{ns, name, replicas})
  key := ns + "/" + name
  if err, ok := m.scaleDeploymentErr[key]; ok {
    return err
  }
  return nil
}

func (m *mockCephKubeClient) ListDeploymentNames(ctx context.Context, ns, labelSelector string) ([]string, error) {
  m.listDeploymentCalls = append(m.listDeploymentCalls, listDeploymentCall{ns, labelSelector})
  key := ns + "/" + labelSelector
  if err, ok := m.listDeploymentErr[key]; ok {
    return nil, err
  }
  if result, ok := m.listDeploymentResult[key]; ok {
    return result, nil
  }
  return []string{}, nil
}

func (m *mockCephKubeClient) IsCephNooutSet(ctx context.Context) (bool, error) {
  m.isCephNooutSetCalls++
  return m.isCephNooutSetResult, m.isCephNooutSetErr
}

// Unused interface methods (required to satisfy KubeClient).
func (m *mockCephKubeClient) GetCNPGClusters(ctx context.Context) ([]clients.CNPGCluster, error) {
  return nil, nil
}
func (m *mockCephKubeClient) SetCNPGHibernation(ctx context.Context, ns, name string, hibernate bool) error {
  return nil
}
func (m *mockCephKubeClient) GetNodes(ctx context.Context) ([]clients.Node, error) {
  return nil, nil
}

func testLogger() *slog.Logger {
  return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelDebug}))
}

func TestCephSetNoout(t *testing.T) {
  mock := newMockCephKubeClient()
  mock.deploymentExistsResult["rook-ceph/rook-ceph-tools"] = true
  phase := NewCephPhase(mock, testLogger())

  err := phase.SetNoout(context.Background())
  if err != nil {
    t.Fatalf("SetNoout() returned error: %v", err)
  }

  if len(mock.execInDeploymentCalls) != 1 {
    t.Fatalf("expected 1 exec call, got %d", len(mock.execInDeploymentCalls))
  }

  call := mock.execInDeploymentCalls[0]
  if call.Ns != "rook-ceph" {
    t.Errorf("exec namespace = %q, want %q", call.Ns, "rook-ceph")
  }
  if call.Deploy != "rook-ceph-tools" {
    t.Errorf("exec deploy = %q, want %q", call.Deploy, "rook-ceph-tools")
  }

  cmd := strings.Join(call.Cmd, " ")
  if cmd != "ceph osd set noout" {
    t.Errorf("exec cmd = %q, want %q", cmd, "ceph osd set noout")
  }
}

func TestCephSetNooutToolsPodMissing(t *testing.T) {
  mock := newMockCephKubeClient()
  mock.deploymentExistsResult["rook-ceph/rook-ceph-tools"] = false
  phase := NewCephPhase(mock, testLogger())

  err := phase.SetNoout(context.Background())
  // Should NOT return error when tools pod is missing (warning only)
  if err != nil {
    t.Fatalf("SetNoout() returned error: %v, want nil (warning only)", err)
  }

  // Should not have attempted exec
  if len(mock.execInDeploymentCalls) != 0 {
    t.Errorf("expected 0 exec calls when tools pod missing, got %d", len(mock.execInDeploymentCalls))
  }
}

func TestCephUnsetNoout(t *testing.T) {
  mock := newMockCephKubeClient()
  mock.deploymentExistsResult["rook-ceph/rook-ceph-tools"] = true
  phase := NewCephPhase(mock, testLogger())

  err := phase.UnsetNoout(context.Background())
  if err != nil {
    t.Fatalf("UnsetNoout() returned error: %v", err)
  }

  if len(mock.execInDeploymentCalls) != 1 {
    t.Fatalf("expected 1 exec call, got %d", len(mock.execInDeploymentCalls))
  }

  cmd := strings.Join(mock.execInDeploymentCalls[0].Cmd, " ")
  if cmd != "ceph osd unset noout" {
    t.Errorf("exec cmd = %q, want %q", cmd, "ceph osd unset noout")
  }
}

func TestCephScaleDown(t *testing.T) {
  mock := newMockCephKubeClient()
  mock.listDeploymentResult["rook-ceph/app=rook-ceph-osd"] = []string{"rook-ceph-osd-0"}
  mock.listDeploymentResult["rook-ceph/app=rook-ceph-mon"] = []string{"rook-ceph-mon-a"}
  mock.listDeploymentResult["rook-ceph/app=rook-ceph-mgr"] = []string{"rook-ceph-mgr-a"}
  phase := NewCephPhase(mock, testLogger())

  err := phase.ScaleDown(context.Background())
  if err != nil {
    t.Fatalf("ScaleDown() returned error: %v", err)
  }

  // Verify correct order: operator -> OSDs -> monitors -> managers
  if len(mock.scaleDeploymentCalls) < 4 {
    t.Fatalf("expected at least 4 scale calls, got %d", len(mock.scaleDeploymentCalls))
  }

  // First call should be operator
  if mock.scaleDeploymentCalls[0].Name != "rook-ceph-operator" {
    t.Errorf("first scale call = %q, want rook-ceph-operator", mock.scaleDeploymentCalls[0].Name)
  }

  // All replicas should be 0
  for _, call := range mock.scaleDeploymentCalls {
    if call.Replicas != 0 {
      t.Errorf("scale %q replicas = %d, want 0", call.Name, call.Replicas)
    }
  }

  // Verify order: operator, then OSD, then mon, then mgr
  names := make([]string, len(mock.scaleDeploymentCalls))
  for i, c := range mock.scaleDeploymentCalls {
    names[i] = c.Name
  }

  operatorIdx := indexOf(names, "rook-ceph-operator")
  osdIdx := indexOf(names, "rook-ceph-osd-0")
  monIdx := indexOf(names, "rook-ceph-mon-a")
  mgrIdx := indexOf(names, "rook-ceph-mgr-a")

  if operatorIdx >= osdIdx {
    t.Errorf("operator (idx %d) should be scaled before OSDs (idx %d)", operatorIdx, osdIdx)
  }
  if osdIdx >= monIdx {
    t.Errorf("OSDs (idx %d) should be scaled before monitors (idx %d)", osdIdx, monIdx)
  }
  if monIdx >= mgrIdx {
    t.Errorf("monitors (idx %d) should be scaled before managers (idx %d)", monIdx, mgrIdx)
  }
}

func TestCephScaleDownMultipleOSDs(t *testing.T) {
  mock := newMockCephKubeClient()
  mock.listDeploymentResult["rook-ceph/app=rook-ceph-osd"] = []string{
    "rook-ceph-osd-0", "rook-ceph-osd-1", "rook-ceph-osd-2",
  }
  mock.listDeploymentResult["rook-ceph/app=rook-ceph-mon"] = []string{"rook-ceph-mon-a"}
  mock.listDeploymentResult["rook-ceph/app=rook-ceph-mgr"] = []string{"rook-ceph-mgr-a"}
  phase := NewCephPhase(mock, testLogger())

  err := phase.ScaleDown(context.Background())
  if err != nil {
    t.Fatalf("ScaleDown() returned error: %v", err)
  }

  // Count OSD scale calls
  osdCount := 0
  for _, call := range mock.scaleDeploymentCalls {
    if strings.HasPrefix(call.Name, "rook-ceph-osd-") {
      osdCount++
    }
  }
  if osdCount != 3 {
    t.Errorf("expected 3 OSD scale calls, got %d", osdCount)
  }
}

func TestCephScaleDownOperatorFails(t *testing.T) {
  mock := newMockCephKubeClient()
  mock.scaleDeploymentErr["rook-ceph/rook-ceph-operator"] = fmt.Errorf("scale failed")
  mock.listDeploymentResult["rook-ceph/app=rook-ceph-osd"] = []string{"rook-ceph-osd-0"}
  mock.listDeploymentResult["rook-ceph/app=rook-ceph-mon"] = []string{"rook-ceph-mon-a"}
  mock.listDeploymentResult["rook-ceph/app=rook-ceph-mgr"] = []string{"rook-ceph-mgr-a"}
  phase := NewCephPhase(mock, testLogger())

  // Should NOT return error (warning only, continues to next component)
  err := phase.ScaleDown(context.Background())
  if err != nil {
    t.Fatalf("ScaleDown() returned error: %v, want nil (warning only)", err)
  }

  // Should still attempt to scale other components
  if len(mock.scaleDeploymentCalls) < 4 {
    t.Errorf("expected at least 4 scale calls (including failed operator), got %d", len(mock.scaleDeploymentCalls))
  }
}

func TestCephScaleUp(t *testing.T) {
  mock := newMockCephKubeClient()
  mock.listDeploymentResult["rook-ceph/app=rook-ceph-osd"] = []string{"rook-ceph-osd-0"}
  mock.listDeploymentResult["rook-ceph/app=rook-ceph-mon"] = []string{"rook-ceph-mon-a"}
  mock.listDeploymentResult["rook-ceph/app=rook-ceph-mgr"] = []string{"rook-ceph-mgr-a"}
  phase := NewCephPhase(mock, testLogger())

  err := phase.ScaleUp(context.Background())
  if err != nil {
    t.Fatalf("ScaleUp() returned error: %v", err)
  }

  // Verify correct order: monitors -> managers -> OSDs -> operator
  if len(mock.scaleDeploymentCalls) < 4 {
    t.Fatalf("expected at least 4 scale calls, got %d", len(mock.scaleDeploymentCalls))
  }

  // All replicas should be 1
  for _, call := range mock.scaleDeploymentCalls {
    if call.Replicas != 1 {
      t.Errorf("scale %q replicas = %d, want 1", call.Name, call.Replicas)
    }
  }

  // Verify order: mon, mgr, osd, operator
  names := make([]string, len(mock.scaleDeploymentCalls))
  for i, c := range mock.scaleDeploymentCalls {
    names[i] = c.Name
  }

  monIdx := indexOf(names, "rook-ceph-mon-a")
  mgrIdx := indexOf(names, "rook-ceph-mgr-a")
  osdIdx := indexOf(names, "rook-ceph-osd-0")
  operatorIdx := indexOf(names, "rook-ceph-operator")

  if monIdx >= mgrIdx {
    t.Errorf("monitors (idx %d) should be scaled before managers (idx %d)", monIdx, mgrIdx)
  }
  if mgrIdx >= osdIdx {
    t.Errorf("managers (idx %d) should be scaled before OSDs (idx %d)", mgrIdx, osdIdx)
  }
  if osdIdx >= operatorIdx {
    t.Errorf("OSDs (idx %d) should be scaled before operator (idx %d)", osdIdx, operatorIdx)
  }
}

func TestCephNeedsRecovery(t *testing.T) {
  t.Run("noout set", func(t *testing.T) {
    mock := newMockCephKubeClient()
    mock.isCephNooutSetResult = true
    phase := NewCephPhase(mock, testLogger())

    needs, err := phase.NeedsRecovery(context.Background())
    if err != nil {
      t.Fatalf("NeedsRecovery() returned error: %v", err)
    }
    if !needs {
      t.Error("NeedsRecovery() = false, want true when noout is set")
    }
  })

  t.Run("noout not set", func(t *testing.T) {
    mock := newMockCephKubeClient()
    mock.isCephNooutSetResult = false
    phase := NewCephPhase(mock, testLogger())

    needs, err := phase.NeedsRecovery(context.Background())
    if err != nil {
      t.Fatalf("NeedsRecovery() returned error: %v", err)
    }
    if needs {
      t.Error("NeedsRecovery() = true, want false when noout is not set")
    }
  })
}

// indexOf returns the index of s in slice, or -1.
func indexOf(slice []string, s string) int {
  for i, v := range slice {
    if v == s {
      return i
    }
  }
  return -1
}
