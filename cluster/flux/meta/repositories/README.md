# Flux Repositories

This directory contains source definitions for Helm charts, OCI images, and upstream Git repositories used by FluxCD in the spruyt-labs cluster. These sources enable Flux to pull and reconcile Helm releases, OCI-based charts, and CRDs vendored directly from upstream tags.

## Directory Structure

- `git/` - Git repository definitions for upstream CRDs, pinned to release tags
- `helm/` - Traditional Helm repository definitions
- `oci/` - OCI repository definitions for container registry-hosted charts

## CRD Sources

`git/` holds the upstream CRD sets that Talos also seeds at bootstrap via `talos/patches/control-plane/extra-manifests.yaml`. Talos creates those objects once and never updates them, so Flux owns updates from that point on — bump the `ref.tag` here, not the URL in the Talos patch. Renovate tracks these tags through its native `flux` manager.
