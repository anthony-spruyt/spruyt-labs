#!/usr/bin/env bash
# shellcheck disable=SC2034 # Variables used by sourcing script (lint.sh)
# Lint configuration - customize per repository
# This file is sourced by lint.sh for both local and CI runs

# MegaLinter Docker image (use digest for reproducibility)
# renovate: datasource=docker depName=ghcr.io/anthony-spruyt/megalinter-spruyt-labs
MEGALINTER_IMAGE="ghcr.io/anthony-spruyt/megalinter-spruyt-labs:v2.0.2@sha256:00bba8bd2384c7dc67c6a5b5f7b97b365a211bca942a8e8ae53958203c3d37e9"

# Skip linting for renovate/dependabot commits in CI
SKIP_BOT_COMMITS=false

# MegaLinter flavor (use "all" for custom images to bypass flavor validation)
MEGALINTER_FLAVOR="all"
