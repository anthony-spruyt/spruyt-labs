package main

import (
	"github.com/prometheus/client_golang/prometheus"
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
