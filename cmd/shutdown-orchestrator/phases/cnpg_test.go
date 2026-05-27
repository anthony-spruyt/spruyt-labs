package phases

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"sync"
	"testing"

	"github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/runtime/schema"
)

// mockKubeClient records calls to CNPG methods.
type mockKubeClient struct {
	mu                sync.Mutex
	clusters          []clients.CNPGCluster
	getClustersErr    error
	setHibernationErr map[string]error // key: "ns/name"
	hibernationCalls  []hibernationCall
}

type hibernationCall struct {
	Namespace string
	Name      string
	Hibernate bool
}

func (m *mockKubeClient) GetCNPGClusters(ctx context.Context) ([]clients.CNPGCluster, error) {
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
func (m *mockKubeClient) GetDeploymentReplicas(ctx context.Context, ns, name string) (int32, error) {
	return 1, nil
}
func (m *mockKubeClient) CordonNode(_ context.Context, _ string) error   { return nil }
func (m *mockKubeClient) UncordonNode(_ context.Context, _ string) error { return nil }
func (m *mockKubeClient) GetPodsOnNode(_ context.Context, _ string) ([]clients.PodInfo, error) {
	return nil, nil
}
func (m *mockKubeClient) DeletePod(_ context.Context, _, _ string, _ int64) error { return nil }

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

func TestCNPGCleanupHibernated(t *testing.T) {
	mock := &mockKubeClient{
		clusters: []clients.CNPGCluster{
			{Namespace: "db", Name: "pg-main", Hibernated: true},
			{Namespace: "db", Name: "pg-replica", Hibernated: true},
		},
	}
	phase := NewCNPGPhase(mock, newTestLogger())

	err := phase.Cleanup(context.Background())
	if err != nil {
		t.Fatalf("Cleanup() returned error: %v", err)
	}

	calls := mock.getHibernationCalls()
	if len(calls) != 2 {
		t.Fatalf("expected 2 cleanup calls, got %d", len(calls))
	}
	for _, c := range calls {
		if c.Hibernate {
			t.Errorf("expected hibernate=false for %s/%s", c.Namespace, c.Name)
		}
	}
}

func TestCNPGCleanupNotHibernated(t *testing.T) {
	mock := &mockKubeClient{
		clusters: []clients.CNPGCluster{
			{Namespace: "db", Name: "pg-main", Hibernated: false},
			{Namespace: "db", Name: "pg-replica", Hibernated: false},
		},
	}
	phase := NewCNPGPhase(mock, newTestLogger())

	err := phase.Cleanup(context.Background())
	if err != nil {
		t.Fatalf("Cleanup() returned error: %v", err)
	}

	calls := mock.getHibernationCalls()
	if len(calls) != 0 {
		t.Fatalf("expected 0 calls for non-hibernated clusters, got %d", len(calls))
	}
}

func TestCNPGCleanupCRDNotInstalled(t *testing.T) {
	noMatchErr := &meta.NoKindMatchError{
		GroupKind:        schema.GroupKind{Group: "postgresql.cnpg.io", Kind: "Cluster"},
		SearchedVersions: []string{"v1"},
	}
	mock := &mockKubeClient{
		getClustersErr: fmt.Errorf("listing CNPG clusters: %w", noMatchErr),
	}
	phase := NewCNPGPhase(mock, newTestLogger())

	err := phase.Cleanup(context.Background())
	if err != nil {
		t.Fatalf("Cleanup() should skip when CRD not found, got error: %v", err)
	}
}
