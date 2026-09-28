# Spegel - Peer-to-Peer Image Mirror

## Overview

Lets nodes pull image layers from each other before going to the upstream registry, cutting external pulls and surviving short registry outages for images already on some node.

## Prerequisites

Two Talos patches make it work; without them Spegel runs but serves nothing useful:

- `talos/patches/all/05-configure-containerd.yaml` sets `discard_unpacked_layers = false`. Containerd otherwise drops compressed layers after unpacking, leaving Spegel nothing to serve.
- `talos/patches/control-plane/03-configure-scheduler-for-spegel.yaml` disables the scheduler's `ImageLocality` score, which would otherwise keep piling pods onto nodes that already have the image.

## Operations

- `containerdRegistryConfigPath` is `/etc/cri/conf.d/hosts` because Talos reads mirror config there, not from the usual `/etc/containerd/certs.d`.
- `resolveTags: false`: tags are always resolved against the real registry, only digests are served from peers. This keeps a stale peer from answering a moving tag.
- The chart's Grafana dashboard is disabled because it uses `${DS_PROMETHEUS}` placeholders that the VictoriaMetrics Grafana sidecar does not substitute ([spegel-org/spegel#1303](https://github.com/spegel-org/spegel/issues/1303)). Re-enable once that is fixed.
