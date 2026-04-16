package main

import (
	"github.com/prometheus/client_golang/prometheus"
	dto "github.com/prometheus/client_model/go"
)

type Metrics struct {
	ReplacementsTotal        prometheus.Counter
	ReplaceFailuresTotal     prometheus.Counter
	SweepsTotal              prometheus.Counter
	CircuitBreakerOpens      prometheus.Counter
	EnqueueBackpressureTotal prometheus.Counter
	EnqueueDropsTotal        prometheus.Counter
	ThreadRetiredTotal       prometheus.Counter
	WorkerRespawnsTotal      prometheus.Counter
}

func NewMetrics(reg prometheus.Registerer) *Metrics {
	m := &Metrics{
		ReplacementsTotal: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kata_tap_qdisc_replacements_total",
			Help: "Total number of tap*_kata qdisc replacements performed.",
		}),
		ReplaceFailuresTotal: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kata_tap_qdisc_replace_failures_total",
			Help: "Total number of failed ApplyReplacement attempts.",
		}),
		SweepsTotal: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kata_tap_qdisc_sweeps_total",
			Help: "Total number of full netns-dir sweeps performed.",
		}),
		CircuitBreakerOpens: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kata_tap_qdisc_circuit_breaker_opens_total",
			Help: "Total number of per-netns circuit-breaker openings.",
		}),
		EnqueueBackpressureTotal: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kata_tap_qdisc_enqueue_backpressure_total",
			Help: "Work-queue was transiently full at first attempt; second attempt succeeded within recovery window.",
		}),
		EnqueueDropsTotal: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kata_tap_qdisc_enqueue_drops_total",
			Help: "Work-queue remained full through the recovery window; item dropped. Indicates real saturation, not transient burst.",
		}),
		ThreadRetiredTotal: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kata_tap_qdisc_thread_retired_total",
			Help: "OS threads retired due to netns-restore failure. Should stay at 0 under normal operation.",
		}),
		WorkerRespawnsTotal: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kata_tap_qdisc_worker_respawns_total",
			Help: "Supervisor restarted the worker goroutine after unexpected exit (typically following a poisoned-thread retirement).",
		}),
	}
	reg.MustRegister(
		m.ReplacementsTotal,
		m.ReplaceFailuresTotal,
		m.SweepsTotal,
		m.CircuitBreakerOpens,
		m.EnqueueBackpressureTotal,
		m.EnqueueDropsTotal,
		m.ThreadRetiredTotal,
		m.WorkerRespawnsTotal,
	)
	return m
}

// counterValue reads a Counter's current value via the prometheus client's
// Collect interface. Used by tests and any in-process health probe.
func counterValue(c prometheus.Counter) float64 {
	var m dto.Metric
	if err := c.Write(&m); err != nil {
		return 0
	}
	if m.Counter == nil || m.Counter.Value == nil {
		return 0
	}
	return *m.Counter.Value
}
