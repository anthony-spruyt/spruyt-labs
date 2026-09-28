# Falco - Runtime Security Monitoring

## Overview

Syscall-level threat detection on every node (modern eBPF driver), alert-only. Falcosidekick forwards events to VictoriaLogs and VictoriaTraces; there is no automated response.

## Prerequisites

- Talos schematics set `lockdown=integrity` (`talos/schematics/*.yaml`). The eBPF driver cannot load under `lockdown=confidentiality`.

## Operations

### Rule exceptions

Workload exceptions live in `app/exceptions-configmap.yaml`, each appended with `override.exceptions: append` so the upstream rule stays intact. Add a new exception there rather than disabling a rule, and match on the narrowest fields that identify the workload (image repository plus namespace, or process path).

`app/kata-tap-qdisc-fix-rules-configmap.yaml` is the reverse: a custom rule that alerts when anything other than `kata-tap-qdisc-fix` calls `setns` into a pod netns on a Kata-ready node, since that DaemonSet is privileged and the behaviour is otherwise indistinguishable from an escape.

### Why falco-talon is disabled

Automated responses (killing pods, adding policies) are not in Git, and Flux reverts them on the next reconcile, so they would only ever be temporary. Enable `falco-talon` only with that in mind.

## Troubleshooting

1. **Alerts missing from VictoriaLogs**
   - **Cause**: Falcosidekick's Loki output posts to `<hostport>/loki/api/v1/push`; VictoriaLogs serves that path under `/insert`.
   - **Fix**: Keep `/insert` at the end of `falcosidekick.config.loki.hostport`.

## References

- [Falco exceptions](https://falco.org/docs/concepts/rules/exceptions/)
