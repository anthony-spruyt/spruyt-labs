# kata-tap-qdisc-fix - Kata Networking Workaround

## Overview

Workaround DaemonSet without which Kata pods have no network at all. Kernel 6.18+ gives `tap` devices the `fq` qdisc, whose horizon check silently drops the Cilium-timestamped reply packets that Kata mirrors into the VM. The daemon swaps the root qdisc on every `tap*_kata` interface to `pfifo_fast`. Root cause and packet traces: [#951](https://github.com/anthony-spruyt/spruyt-labs/issues/951).
Source, env vars and the dry-run canary procedure: [anthony-spruyt/kata-tap-qdisc-fix](https://github.com/anthony-spruyt/kata-tap-qdisc-fix).

## Operations

- **Removal condition**: when a Kata/cloud-hypervisor or kernel release stops creating taps with `fq` (or Kata sets the qdisc itself), `kata_tap_qdisc_replacements_total` stays flat on new Kata pods. Delete this app and the paired Falco rule together then.
- **Why it is privileged**: it must `setns()` into netns owned by the host user namespace and unmask `/proc/<pid>/ns/net`. `hostUsers: false` with `procMount: Unmasked` would scope `CAP_SYS_ADMIN` to the pod userns and break that; the full reasoning is in the comments in `app/values.yaml`. The deny-all egress CNP and the Falco rule in
  `falco-system/falco/app/kata-tap-qdisc-fix-rules-configmap.yaml` are the compensating controls.
- It runs only where the `kata` RuntimeClass can schedule (`kata.spruyt-labs/ready=true`). Extending Kata to a new node extends this automatically.

## Troubleshooting

1. **New Kata pod has no network (DNS and ping fail, Hubble shows no flows)**
   - **Cause**: The DaemonSet is not running on that node, or is in `DRY_RUN`.
   - **Fix**: Check the pod on the node and `kata_tap_qdisc_replace_failures_total`; confirm `DRY_RUN` is `"false"`.
