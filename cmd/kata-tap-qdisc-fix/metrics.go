package main

import (
	"github.com/prometheus/client_golang/prometheus"
	dto "github.com/prometheus/client_model/go"
)

type Metrics struct {
	ReplacementsTotal    prometheus.Counter
	ReplaceFailuresTotal prometheus.Counter
	SweepsTotal          prometheus.Counter
}

func NewMetrics(reg prometheus.Registerer) *Metrics {
	m := &Metrics{
		ReplacementsTotal: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kata_tap_qdisc_replacements_total",
			Help: "Total number of tap*_kata qdisc replacements performed.",
		}),
		ReplaceFailuresTotal: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kata_tap_qdisc_replace_failures_total",
			Help: "Total number of failed sweep attempts.",
		}),
		SweepsTotal: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "kata_tap_qdisc_sweeps_total",
			Help: "Total number of full /proc sweeps performed.",
		}),
	}
	reg.MustRegister(
		m.ReplacementsTotal,
		m.ReplaceFailuresTotal,
		m.SweepsTotal,
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
