#!/usr/bin/env bash
# shellcheck disable=SC2034 # Variables used by sourcing script (lint.sh)
# Lint configuration - customize per repository
# This file is sourced by lint.sh for both local and CI runs

# MegaLinter Docker image (use digest for reproducibility)
# renovate: datasource=docker depName=ghcr.io/anthony-spruyt/megalinter-spruyt-labs
MEGALINTER_IMAGE="ghcr.io/anthony-spruyt/megalinter-spruyt-labs:v1.0.13@sha256:413000bef82163a05fd23caa8478200b2de2acfd11905fcb580bc24bc18015e7"

# Skip linting for renovate/dependabot commits in CI
SKIP_BOT_COMMITS=true

# MegaLinter flavor (use "all" for custom images to bypass flavor validation)
MEGALINTER_FLAVOR="all"
