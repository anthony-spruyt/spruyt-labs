package clients

import (
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
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
