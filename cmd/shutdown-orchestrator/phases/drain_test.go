package phases

import (
	"context"
	"testing"
	"time"

	"github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator/clients"
)

// drainMockKube implements clients.KubeClient for drain phase tests.
type drainMockKube struct {
	cordonedNodes   []string
	uncordonedNodes []string
	deletedPods     []string
	podsByNode      map[string][]clients.PodInfo
	cordonErr       error
	uncordonErr     error
	neverTerminate  bool // if true, DeletePod does not remove pods from podsByNode
}

func (m *drainMockKube) CordonNode(_ context.Context, name string) error {
	if m.cordonErr != nil {
		return m.cordonErr
	}
	m.cordonedNodes = append(m.cordonedNodes, name)
	return nil
}

func (m *drainMockKube) UncordonNode(_ context.Context, name string) error {
	if m.uncordonErr != nil {
		return m.uncordonErr
	}
	m.uncordonedNodes = append(m.uncordonedNodes, name)
	return nil
}

func (m *drainMockKube) GetPodsOnNode(_ context.Context, nodeName string) ([]clients.PodInfo, error) {
	return m.podsByNode[nodeName], nil
}

func (m *drainMockKube) DeletePod(_ context.Context, ns, name string, _ int64) error {
	m.deletedPods = append(m.deletedPods, ns+"/"+name)
	if m.neverTerminate {
		return nil
	}
	for nodeName, pods := range m.podsByNode {
		filtered := make([]clients.PodInfo, 0, len(pods))
		for _, p := range pods {
			if !(p.Namespace == ns && p.Name == name) {
				filtered = append(filtered, p)
			}
		}
		m.podsByNode[nodeName] = filtered
	}
	return nil
}

// Unused KubeClient stubs.
func (m *drainMockKube) GetCNPGClusters(_ context.Context) ([]clients.CNPGCluster, error) {
	return nil, nil
}
func (m *drainMockKube) SetCNPGHibernation(_ context.Context, _, _ string, _ bool) error { return nil }
func (m *drainMockKube) DeploymentExists(_ context.Context, _, _ string) (bool, error) {
	return false, nil
}
func (m *drainMockKube) ExecInDeployment(_ context.Context, _, _ string, _ []string) (string, error) {
	return "", nil
}
func (m *drainMockKube) ScaleDeployment(_ context.Context, _, _ string, _ int32) error { return nil }
func (m *drainMockKube) ListDeploymentNames(_ context.Context, _, _ string) ([]string, error) {
	return nil, nil
}
func (m *drainMockKube) GetDeploymentReplicas(_ context.Context, _, _ string) (int32, error) {
	return 1, nil
}
func (m *drainMockKube) GetNodes(_ context.Context) ([]clients.Node, error) { return nil, nil }
func (m *drainMockKube) IsCephNooutSet(_ context.Context) (bool, error)     { return false, nil }

func TestDrainCordonWorkers(t *testing.T) {
	mock := &drainMockKube{}
	phase := NewDrainPhase(mock, newNodeTestLogger())

	workers := []string{"worker-1", "worker-2"}
	if err := phase.CordonWorkers(context.Background(), workers); err != nil {
		t.Fatalf("CordonWorkers() error: %v", err)
	}
	if len(mock.cordonedNodes) != 2 {
		t.Fatalf("expected 2 cordoned nodes, got %d", len(mock.cordonedNodes))
	}
	for i, name := range workers {
		if mock.cordonedNodes[i] != name {
			t.Errorf("cordoned[%d] = %s, want %s", i, mock.cordonedNodes[i], name)
		}
	}
}

func TestDrainUncordonWorkers(t *testing.T) {
	mock := &drainMockKube{}
	phase := NewDrainPhase(mock, newNodeTestLogger())

	workers := []string{"worker-1", "worker-2"}
	if err := phase.UncordonWorkers(context.Background(), workers); err != nil {
		t.Fatalf("UncordonWorkers() error: %v", err)
	}
	if len(mock.uncordonedNodes) != 2 {
		t.Fatalf("expected 2 uncordoned nodes, got %d", len(mock.uncordonedNodes))
	}
	for i, name := range workers {
		if mock.uncordonedNodes[i] != name {
			t.Errorf("uncordoned[%d] = %s, want %s", i, mock.uncordonedNodes[i], name)
		}
	}
}

func TestDrainEvictWorkloadsSkipsDaemonSets(t *testing.T) {
	mock := &drainMockKube{
		podsByNode: map[string][]clients.PodInfo{
			"worker-1": {
				{Namespace: "default", Name: "app-pod", NodeName: "worker-1", DaemonSet: false},
				{Namespace: "default", Name: "ds-pod", NodeName: "worker-1", DaemonSet: true},
			},
		},
	}
	phase := NewDrainPhase(mock, newNodeTestLogger())

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := phase.EvictWorkloads(ctx, []string{"worker-1"}, nil, 30); err != nil {
		t.Fatalf("EvictWorkloads() error: %v", err)
	}
	if len(mock.deletedPods) != 1 {
		t.Fatalf("expected 1 deleted pod, got %d: %v", len(mock.deletedPods), mock.deletedPods)
	}
	if mock.deletedPods[0] != "default/app-pod" {
		t.Errorf("deleted pod = %s, want default/app-pod", mock.deletedPods[0])
	}
}

func TestDrainEvictWorkloadsSkipsExcludedNamespaces(t *testing.T) {
	mock := &drainMockKube{
		podsByNode: map[string][]clients.PodInfo{
			"worker-1": {
				{Namespace: "default", Name: "app-pod", NodeName: "worker-1"},
				{Namespace: "rook-ceph", Name: "osd-pod", NodeName: "worker-1"},
				{Namespace: "kube-system", Name: "cni-pod", NodeName: "worker-1"},
			},
		},
	}
	phase := NewDrainPhase(mock, newNodeTestLogger())

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := phase.EvictWorkloads(ctx, []string{"worker-1"}, []string{"rook-ceph", "kube-system"}, 30); err != nil {
		t.Fatalf("EvictWorkloads() error: %v", err)
	}
	if len(mock.deletedPods) != 1 {
		t.Fatalf("expected 1 deleted pod, got %d: %v", len(mock.deletedPods), mock.deletedPods)
	}
	if mock.deletedPods[0] != "default/app-pod" {
		t.Errorf("deleted pod = %s, want default/app-pod", mock.deletedPods[0])
	}
}

func TestDrainEvictWorkloadsWaitsForTermination(t *testing.T) {
	mock := &drainMockKube{
		podsByNode: map[string][]clients.PodInfo{
			"worker-1": {
				{Namespace: "default", Name: "slow-pod", NodeName: "worker-1"},
			},
		},
	}
	phase := NewDrainPhase(mock, newNodeTestLogger())

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := phase.EvictWorkloads(ctx, []string{"worker-1"}, nil, 30); err != nil {
		t.Fatalf("EvictWorkloads() error: %v", err)
	}
	if len(mock.deletedPods) != 1 {
		t.Errorf("expected 1 deleted pod, got %d", len(mock.deletedPods))
	}
}

func TestDrainEvictWorkloadsTimeout(t *testing.T) {
	mock := &drainMockKube{
		podsByNode: map[string][]clients.PodInfo{
			"worker-1": {
				{Namespace: "default", Name: "stuck-pod", NodeName: "worker-1"},
			},
		},
		neverTerminate: true,
	}
	phase := NewDrainPhase(mock, newNodeTestLogger())

	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()

	err := phase.EvictWorkloads(ctx, []string{"worker-1"}, nil, 30)
	if err == nil {
		t.Fatal("EvictWorkloads() should return error when context cancelled with stuck pods")
	}
}

func TestDrainEvictWorkloadsNoPods(t *testing.T) {
	mock := &drainMockKube{
		podsByNode: map[string][]clients.PodInfo{},
	}
	phase := NewDrainPhase(mock, newNodeTestLogger())

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := phase.EvictWorkloads(ctx, []string{"worker-1", "worker-2"}, nil, 30); err != nil {
		t.Fatalf("EvictWorkloads() with no pods error: %v", err)
	}
	if len(mock.deletedPods) != 0 {
		t.Errorf("expected 0 deleted pods, got %d", len(mock.deletedPods))
	}
}
