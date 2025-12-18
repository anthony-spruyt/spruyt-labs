# Flux Repositories

This directory contains repository definitions for Helm charts and OCI images used by FluxCD in the spruyt-labs cluster. These repositories enable Flux to pull and reconcile Helm releases and OCI-based charts.

## Directory Structure

- `git/` - Git repository definitions
- `helm/` - Traditional Helm repository definitions
- `oci/` - OCI repository definitions for container registry-hosted charts

## Management

Repository definitions are reconciled by Flux and referenced in HelmRelease manifests. When adding new charts:

1. Add the repository definition here
2. Reference it in the corresponding HelmRelease `spec.chart.spec.sourceRef`
3. Update the kustomization to include the new repository
