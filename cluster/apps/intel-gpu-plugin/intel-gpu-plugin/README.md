# intel-gpu-plugin - Intel iGPU device plugin for the MS-01 workers

## Overview

Advertises each MS-01 worker's Iris Xe iGPU to the scheduler as `gpu.intel.com/i915`, so a pod such as the `llm-tool-guard` scanner can request it. It runs on the nodes that carry the Talos i915 extension label, with no operator and no Node Feature Discovery.

## Prerequisites

- The Talos `i915` system extension, in [`talos/schematics/ms-01.yaml`](../../../../talos/schematics/ms-01.yaml). It sets the `extensions.talos.dev/i915` label the DaemonSet's `nodeAffinity` matches.
- The udev rule in [`talos/patches/worker/04-enable-gpu-passthrough.yaml`](../../../../talos/patches/worker/04-enable-gpu-passthrough.yaml), which makes `/dev/dri/renderD*` `root:44` with mode `0660`.

## Operations

- `-shared-dev-num=2` lets two pods share each GPU, so each node offers two `gpu.intel.com/i915`. A second slot lets a rollout's surge pod schedule while the first pod still holds a GPU.
- A consumer that does not run as root must add `supplementalGroups: [44]` to open `/dev/dri/renderD128`. The `gpu.intel.com/i915` request alone mounts the device node but grants no access to it.
- The namespace is PSA `privileged` and excluded from `pss-restricted-defaults`: the image runs as root and mounts host paths, and the injected `runAsNonRoot: true` would stop it starting.

### Checking the result

```bash
# Allocatable should read 2 on each ms-01 node and be empty on the e2 nodes
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.gpu\.intel\.com/i915'
```

## References

- [Intel GPU device plugin](https://github.com/intel/intel-device-plugins-for-kubernetes/blob/main/cmd/gpu_plugin/README.md)
