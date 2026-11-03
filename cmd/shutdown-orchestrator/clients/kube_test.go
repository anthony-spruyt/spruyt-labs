package clients

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes/fake"
)

func TestPodInfoFromPodReportsPhase(t *testing.T) {
	pod := &corev1.Pod{Status: corev1.PodStatus{Phase: corev1.PodSucceeded}}

	if got := podInfoFromPod(pod).Phase; got != "Succeeded" {
		t.Errorf("Phase = %q, want Succeeded", got)
	}
}

func TestPodInfoFromPodReportsTerminating(t *testing.T) {
	now := metav1.NewTime(time.Now())
	terminating := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{DeletionTimestamp: &now}}
	running := &corev1.Pod{}

	if !podInfoFromPod(terminating).Terminating {
		t.Error("pod with a deletionTimestamp should be Terminating")
	}
	if podInfoFromPod(running).Terminating {
		t.Error("pod without a deletionTimestamp should not be Terminating")
	}
}

func testNode(name string, unschedulable bool, annotations map[string]string) *corev1.Node {
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: name, Annotations: annotations},
		Spec:       corev1.NodeSpec{Unschedulable: unschedulable},
	}
}

func newFakeKube(nodes ...*corev1.Node) (*RealKubeClient, *fake.Clientset) {
	cs := fake.NewClientset()
	for _, n := range nodes {
		if _, err := cs.CoreV1().Nodes().Create(context.Background(), n, metav1.CreateOptions{}); err != nil {
			panic(err)
		}
	}
	cs.ClearActions()
	return &RealKubeClient{clientset: cs}, cs
}

func getNode(t *testing.T, cs *fake.Clientset, name string) *corev1.Node {
	t.Helper()
	n, err := cs.CoreV1().Nodes().Get(context.Background(), name, metav1.GetOptions{})
	if err != nil {
		t.Fatalf("getting node %s: %v", name, err)
	}
	return n
}

func nodePatchCount(cs *fake.Clientset, name string) int {
	count := 0
	for _, a := range cs.Actions() {
		if a.Matches("patch", "nodes") && a.(interface{ GetName() string }).GetName() == name {
			count++
		}
	}
	return count
}

func TestCordonNodeMarksSchedulableNodeInOnePatch(t *testing.T) {
	kube, cs := newFakeKube(testNode("w1", false, nil))

	if err := kube.CordonNode(context.Background(), "w1"); err != nil {
		t.Fatalf("CordonNode() error: %v", err)
	}

	n := getNode(t, cs, "w1")
	if !n.Spec.Unschedulable {
		t.Error("node should be cordoned")
	}
	if _, ok := n.Annotations[CordonAnnotation]; !ok {
		t.Errorf("node cordoned from schedulable should carry %s", CordonAnnotation)
	}
	if got := nodePatchCount(cs, "w1"); got != 1 {
		t.Errorf("cordon and mark must be one patch, got %d patches", got)
	}
}

func TestCordonNodeDoesNotMarkHandCordonedNode(t *testing.T) {
	kube, cs := newFakeKube(testNode("w1", true, nil))

	if err := kube.CordonNode(context.Background(), "w1"); err != nil {
		t.Fatalf("CordonNode() error: %v", err)
	}

	n := getNode(t, cs, "w1")
	if !n.Spec.Unschedulable {
		t.Error("hand-cordoned node should stay cordoned")
	}
	if _, ok := n.Annotations[CordonAnnotation]; ok {
		t.Errorf("node that was already cordoned must not get %s", CordonAnnotation)
	}
}

func TestCordonNodeKeepsMarkOnNodeAlreadyMarked(t *testing.T) {
	kube, cs := newFakeKube(testNode("w1", true, map[string]string{CordonAnnotation: "true"}))

	if err := kube.CordonNode(context.Background(), "w1"); err != nil {
		t.Fatalf("CordonNode() error: %v", err)
	}

	if _, ok := getNode(t, cs, "w1").Annotations[CordonAnnotation]; !ok {
		t.Errorf("a second cordon must not drop %s", CordonAnnotation)
	}
}

func TestUncordonNodeClearsMarkInOnePatch(t *testing.T) {
	kube, cs := newFakeKube(testNode("w1", true, map[string]string{CordonAnnotation: "true", "keep": "me"}))

	if err := kube.UncordonNode(context.Background(), "w1"); err != nil {
		t.Fatalf("UncordonNode() error: %v", err)
	}

	n := getNode(t, cs, "w1")
	if n.Spec.Unschedulable {
		t.Error("node should be schedulable")
	}
	if _, ok := n.Annotations[CordonAnnotation]; ok {
		t.Errorf("uncordon should remove %s", CordonAnnotation)
	}
	if n.Annotations["keep"] != "me" {
		t.Error("uncordon must leave other annotations alone")
	}
	if got := nodePatchCount(cs, "w1"); got != 1 {
		t.Errorf("uncordon and unmark must be one patch, got %d patches", got)
	}
}

func TestUncordonNodeUncordonsUnmarkedNode(t *testing.T) {
	kube, cs := newFakeKube(testNode("w1", true, nil))

	if err := kube.UncordonNode(context.Background(), "w1"); err != nil {
		t.Fatalf("UncordonNode() error: %v", err)
	}

	if getNode(t, cs, "w1").Spec.Unschedulable {
		t.Error("recovery uncordons every worker, marked or not")
	}
}

func TestGetNodesReportsCordonMark(t *testing.T) {
	kube, _ := newFakeKube(
		testNode("marked", true, map[string]string{CordonAnnotation: "true"}),
		testNode("by-hand", true, nil),
	)

	nodes, err := kube.GetNodes(context.Background())
	if err != nil {
		t.Fatalf("GetNodes() error: %v", err)
	}

	got := map[string]bool{}
	for _, n := range nodes {
		got[n.Name] = n.CordonedByShutdown
	}
	if !got["marked"] {
		t.Error("node with the annotation should report CordonedByShutdown")
	}
	if got["by-hand"] {
		t.Error("node without the annotation should not report CordonedByShutdown")
	}
}
