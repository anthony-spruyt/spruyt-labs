package main

import (
	"testing"

	"github.com/prometheus/client_golang/prometheus"
)

func TestNewMetricsRegistersWithoutPanic(t *testing.T) {
	reg := prometheus.NewRegistry()
	m := NewMetrics(reg)
	if m.ReplacementsTotal == nil || m.ReplaceFailuresTotal == nil ||
		m.SweepsTotal == nil || m.CircuitBreakerOpens == nil ||
		m.EnqueueBackpressureTotal == nil || m.EnqueueDropsTotal == nil ||
		m.ThreadRetiredTotal == nil || m.WorkerRespawnsTotal == nil {
		t.Fatal("one or more metrics are nil")
	}
	m.ReplacementsTotal.Inc()
	m.SweepsTotal.Inc()
	mf, err := reg.Gather()
	if err != nil {
		t.Fatal(err)
	}
	if len(mf) < 2 {
		t.Errorf("expected ≥2 metric families, got %d", len(mf))
	}
}

func newTestMetrics() *Metrics {
	return NewMetrics(prometheus.NewRegistry())
}

// testCounterValue is the assertion helper used from watcher_test.go.
func testCounterValue(t *testing.T, c prometheus.Counter) int {
	t.Helper()
	return int(counterValue(c))
}
