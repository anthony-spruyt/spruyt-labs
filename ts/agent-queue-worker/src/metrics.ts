import { Counter, Gauge, Histogram, Registry } from "prom-client";

export const registry = new Registry();
registry.setDefaultLabels({ service: "agent-queue-worker" });

export const queueDepth = new Gauge({
  name: "agent_queue_depth",
  help: "Jobs waiting in queue",
  labelNames: ["queue"] as const,
  registers: [registry],
});

export const queuePaused = new Gauge({
  name: "agent_queue_paused",
  help: "Whether the queue is paused (1=paused, 0=active)",
  labelNames: ["queue"] as const,
  registers: [registry],
});

export const jobDuration = new Histogram({
  name: "agent_job_duration_seconds",
  help: "Job processing time",
  labelNames: ["queue", "role"] as const,
  buckets: [10, 30, 60, 120, 300, 600, 1200, 1800, 3600],
  registers: [registry],
});

export const jobFailures = new Counter({
  name: "agent_job_failures_total",
  help: "Job failures",
  labelNames: ["queue", "role", "reason"] as const,
  registers: [registry],
});

export const jobTimeouts = new Counter({
  name: "agent_job_timeout_total",
  help: "Job timeouts",
  labelNames: ["queue", "role"] as const,
  registers: [registry],
});

export const staleDiscards = new Counter({
  name: "agent_stale_total",
  help: "Stale job discards",
  labelNames: ["queue", "role"] as const,
  registers: [registry],
});

export const jobExhausted = new Counter({
  name: "agent_job_exhausted_total",
  help: "Jobs that exhausted all retry attempts",
  labelNames: ["queue", "role", "repo"] as const,
  registers: [registry],
});

export const workerShutdowns = new Counter({
  name: "agent_worker_shutdown_total",
  help: "Graceful shutdown counter",
  registers: [registry],
});

export const dedupActionCounter = new Counter({
  name: "agent_dedup_action_total",
  help: "Dedup actions by strategy",
  labelNames: ["queue", "role", "action"] as const,
  registers: [registry],
});

export const sreBatchSize = new Histogram({
  name: "agent_sre_batch_size",
  help: "Total alerts per SRE batch (trigger + buffered)",
  buckets: [1, 5, 10, 20, 50],
  registers: [registry],
});

export const sreSuppressed = new Counter({
  name: "agent_sre_suppressed_total",
  help: "Alerts suppressed by fingerprint dedup",
  labelNames: ["role"] as const,
  registers: [registry],
});

export const healthPauses = new Counter({
  name: "agent_health_pause_total",
  help: "Dependency health gate pauses",
  labelNames: ["reason"] as const,
  registers: [registry],
});
