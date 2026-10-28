# drm-exporter - GPU busy and frequency metrics for the MS-01 workers

## Overview

Exports how busy each MS-01 iGPU is (per engine) and its clock, read from the i915 PMU, so the `llm-tool-guard` scanner's latency can be read next to GPU load. vmagent scrapes it through the `drm-exporter` `VMPodScrape`; the metrics are `drm_engine_utilization_ratio` and `drm_frequency_hertz`, and the `node` label comes from the pod's node name.

## Prerequisites

- The plugin runs with `-enable-monitoring` ([`intel-gpu-plugin`](../intel-gpu-plugin/README.md)). The exporter requests `gpu.intel.com/monitoring: 1`, which is what gives it the GPU on a node; a node without that resource leaves the pod `Pending`.
- The Talos `i915` extension label, which the `nodeAffinity` matches.

## Operations

- It runs as root with only `CAP_PERFMON` and a read-only `/sys` host mount. Talos sets `kernel.perf_event_paranoid=3`, so reading the PMU needs `CAP_PERFMON`; a non-root user would lose it, because Kubernetes grants no ambient capabilities to non-root users.
- The upstream docs also list `SYS_RAWIO` and a `/dev/cpu` mount. Those read per-CPU MSRs through the `msr` module, which Talos does not ship, so they are left out. Only the iGPU package temperature is lost; engine, frequency and power metrics are unaffected.
- `DRM_EXPORTER_INTERVAL_SECONDS` and the `VMPodScrape` interval are both 15 seconds. Change them together.
- Dashboard: the GPU row of the `LLM Tool Guard` dashboard in Grafana.

## Troubleshooting

1. **Pod `Pending`, event `Insufficient gpu.intel.com/monitoring`**

   - **Cause**: The plugin pod on that node has not restarted with `-enable-monitoring`, or is not running.
   - **Fix**: Check `kubectl get nodes -o custom-columns='NAME:.metadata.name,MON:.status.allocatable.gpu\.intel\.com/monitoring'` and the plugin pod on the node.

2. **Pod starts but `drm_engine_utilization_ratio` is missing**

   - **Cause**: The PMU could not be opened, so the pod's log reports the engine PMU init failing.
   - **Fix**: Confirm the container still has `CAP_PERFMON` and runs as UID 0.

## References

- [home-operations/drm-exporter](https://github.com/home-operations/drm-exporter)
