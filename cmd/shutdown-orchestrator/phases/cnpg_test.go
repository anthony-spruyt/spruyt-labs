package phases

import (
  "context"
  "fmt"
  "io"
  "log/slog"
  "sync"
  "testing"
  "time"

  "github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
)

// mockKubeClient records calls to CNPG methods.
type mockKubeClient struct {
  mu                    sync.Mutex
  clusters              []clients.CNPGCluster
  getClustersErr        error
  setHibernationErr     map[string]error // key: "ns/name"
  hibernationCalls      []hibernationCall
  getClustersBlockForever bool
}

type hibernationCall struct {
  Namespace string
  Name      string
  Hibernate bool
}

func (m *mockKubeClient) GetCNPGClusters(ctx context.Context) ([]clients.CNPGCluster, error) {
  if m.getClustersBlockForever {
    <-ctx.Done()
    return nil, ctx.Err()
  }
  return m.clusters, m.getClustersErr
}

func (m *mockKubeClient) SetCNPGHibernation(ctx context.Context, ns, name string, hibernate bool) error {
  m.mu.Lock()
  defer m.mu.Unlock()
  m.hibernationCalls = append(m.hibernationCalls, hibernationCall{
    Namespace: ns,
    Name:      name,
    Hibernate: hibernate,
  })
  key := ns + "/" + name
  if err, ok := m.setHibernationErr[key]; ok {
    return err
  }
  return nil
}

// Unused interface methods — return zero values.
func (m *mockKubeClient) DeploymentExists(ctx context.Context, ns, name string) (bool, error) {
  return false, nil
}
func (m *mockKubeClient) ExecInDeployment(ctx context.Context, ns, deploy string, cmd []string) (string, error) {
  return "", nil
}
func (m *mockKubeClient) ScaleDeployment(ctx context.Context, ns, name string, replicas int32) error {
  return nil
}
func (m *mockKubeClient) ListDeploymentNames(ctx context.Context, ns, labelSelector string) ([]string, error) {
  return nil, nil
}
func (m *mockKubeClient) GetNodes(ctx context.Context) ([]clients.Node, error) {
  return nil, nil
}
func (m *mockKubeClient) IsCephNooutSet(ctx context.Context) (bool, error) {
  return false, nil
}

func (m *mockKubeClient) getHibernationCalls() []hibernationCall {
  m.mu.Lock()
  defer m.mu.Unlock()
  out := make([]hibernationCall, len(m.hibernationCalls))
  copy(out, m.hibernationCalls)
  return out
}

func newTestLogger() *slog.Logger {
  return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func TestCNPGHibernateAll(t *testing.T) {
  mock := &mockKubeClient{
    clusters: []clients.CNPGCluster{
      {Namespace: "db", Name: "pg-main", Hibernated: false},
      {Namespace: "db", Name: "pg-replica", Hibernated: false},
    },
  }
  phase := NewCNPGPhase(mock, newTestLogger())

  err := phase.Hibernate(context.Background())
  if err != nil {
    t.Fatalf("Hibernate() returned error: %v", err)
  }

  calls := mock.getHibernationCalls()
  if len(calls) != 2 {
    t.Fatalf("expected 2 hibernation calls, got %d", len(calls))
  }
  for _, c := range calls {
    if !c.Hibernate {
      t.Errorf("expected hibernate=true for %s/%s", c.Namespace, c.Name)
    }
  }
}

func TestCNPGHibernateNoClusters(t *testing.T) {
  mock := &mockKubeClient{
    clusters: []clients.CNPGCluster{},
  }
  phase := NewCNPGPhase(mock, newTestLogger())

  err := phase.Hibernate(context.Background())
  if err != nil {
    t.Fatalf("Hibernate() returned error: %v", err)
  }

  calls := mock.getHibernationCalls()
  if len(calls) != 0 {
    t.Fatalf("expected 0 hibernation calls, got %d", len(calls))
  }
}

func TestCNPGHibernateCRDNotInstalled(t *testing.T) {
  mock := &mockKubeClient{
    getClustersErr: fmt.Errorf("the server could not find the requested resource: not found"),
  }
  phase := NewCNPGPhase(mock, newTestLogger())

  err := phase.Hibernate(context.Background())
  if err != nil {
    t.Fatalf("Hibernate() should skip when CRD not found, got error: %v", err)
  }
}

func TestCNPGHibernateAnnotationFailure(t *testing.T) {
  mock := &mockKubeClient{
    clusters: []clients.CNPGCluster{
      {Namespace: "db", Name: "pg-main", Hibernated: false},
      {Namespace: "db", Name: "pg-replica", Hibernated: false},
    },
    setHibernationErr: map[string]error{
      "db/pg-main": fmt.Errorf("connection refused"),
    },
  }
  phase := NewCNPGPhase(mock, newTestLogger())

  err := phase.Hibernate(context.Background())
  if err != nil {
    t.Fatalf("Hibernate() returned error: %v", err)
  }

  calls := mock.getHibernationCalls()
  if len(calls) != 2 {
    t.Fatalf("expected 2 hibernation calls (both attempted), got %d", len(calls))
  }
}

func TestCNPGWakeAll(t *testing.T) {
  mock := &mockKubeClient{
    clusters: []clients.CNPGCluster{
      {Namespace: "db", Name: "pg-main", Hibernated: true},
      {Namespace: "db", Name: "pg-replica", Hibernated: true},
    },
  }
  phase := NewCNPGPhase(mock, newTestLogger())

  err := phase.Wake(context.Background())
  if err != nil {
    t.Fatalf("Wake() returned error: %v", err)
  }

  calls := mock.getHibernationCalls()
  if len(calls) != 2 {
    t.Fatalf("expected 2 wake calls, got %d", len(calls))
  }
  for _, c := range calls {
    if c.Hibernate {
      t.Errorf("expected hibernate=false for %s/%s", c.Namespace, c.Name)
    }
  }
}

func TestCNPGContextTimeout(t *testing.T) {
  mock := &mockKubeClient{
    getClustersBlockForever: true,
  }
  phase := NewCNPGPhase(mock, newTestLogger())

  ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
  defer cancel()

  err := phase.Hibernate(ctx)
  if err == nil {
    t.Fatal("Hibernate() should return error on context cancellation")
  }
  if ctx.Err() == nil {
    t.Fatal("context should be done")
  }
}
